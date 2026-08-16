import Foundation
import Synchronization

/// A parsed view of `swift package describe --type json` output. Captures just
/// what diagram generation needs: each target's name, type, source-root path,
/// and the source files within.
public struct SPMPackageDescription: Sendable, Equatable {
    public let name: String
    public let targets: [SPMTargetDescription]

    public init(name: String, targets: [SPMTargetDescription]) {
        self.name = name
        self.targets = targets
    }

    /// Build a `[absoluteFilePath: moduleName]` map across all (non-test)
    /// targets in the package. The returned paths have already been joined
    /// with each target's `path` so they are absolute and ready to compare
    /// against `URL.path` strings produced by `FileCollector`.
    public func sourceFileToModuleMap(packageRoot: URL) -> [String: String] {
        var map: [String: String] = [:]
        for target in targets where target.kind != .test {
            let targetRoot = packageRoot.appendingPathComponent(target.path)
            for source in target.sources {
                let absolute = targetRoot.appendingPathComponent(source).path
                map[absolute] = target.name
            }
        }
        return map
    }
}

/// A single target inside a parsed `SPMPackageDescription`.
public struct SPMTargetDescription: Sendable, Equatable {
    public let name: String
    public let kind: Kind
    public let path: String
    public let sources: [String]
    public let dependencies: [String]

    /// The target's kind. One shared `ComponentKind`, also used by the UML `Component` model.
    public typealias Kind = ComponentKind

    public init(
        name: String, kind: Kind, path: String,
        sources: [String], dependencies: [String]
    ) {
        self.name = name
        self.kind = kind
        self.path = path
        self.sources = sources
        self.dependencies = dependencies
    }
}

/// Reads SPM package descriptions. The pure `parse` step is unit-testable;
/// `describe(at:)` shells out to `swift package describe --type json`.
public enum SPMPackageReader {
    public enum ReadError: Error, Equatable {
        case swiftToolFailed(exitStatus: Int32, stderr: String)
        case malformedJSON(String)
        /// `swift package describe` outlived `describeTimeout` and was killed.
        case timedOut(seconds: TimeInterval)
    }

    /// Parse JSON output produced by `swift package describe --type json`.
    public static func parse(_ data: Data) throws -> SPMPackageDescription {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let dict = root as? [String: Any]
        else {
            throw ReadError.malformedJSON("not a JSON object")
        }
        guard let name = dict["name"] as? String else {
            throw ReadError.malformedJSON("missing 'name'")
        }
        let targetDicts = (dict["targets"] as? [[String: Any]]) ?? []
        let targets = targetDicts.compactMap(parseTarget(_:))
        return SPMPackageDescription(name: name, targets: targets)
    }

    private static func parseTarget(_ dict: [String: Any]) -> SPMTargetDescription? {
        guard let name = dict["name"] as? String,
              let path = dict["path"] as? String
        else { return nil }
        let kindString = dict["type"] as? String ?? ""
        let kind = SPMTargetDescription.Kind(rawValue: kindString) ?? .other
        let sources = (dict["sources"] as? [String]) ?? []
        let dependencies = (dict["target_dependencies"] as? [String]) ?? []
        return SPMTargetDescription(
            name: name, kind: kind, path: path,
            sources: sources, dependencies: dependencies
        )
    }

    /// How long `swift package describe` may run before it is killed and
    /// `ReadError.timedOut` is thrown.
    ///
    /// Deliberately generous. Describing a package resolves its dependencies,
    /// which on a machine that has never seen them means cloning from the
    /// network — minutes, legitimately. The limit exists to convert a *hang*
    /// into an actionable error, not to bound normal work, so it is set far
    /// above any plausible honest run.
    public static let describeTimeout: TimeInterval = 300

    /// Run `swift package describe --type json` against the package at
    /// `packageRoot` (the directory containing `Package.swift`).
    ///
    /// - Throws: `ReadError.timedOut` if the tool outlives `describeTimeout`,
    ///   `ReadError.swiftToolFailed` on a non-zero exit, `ReadError.malformedJSON`
    ///   if the output cannot be parsed.
    public static func describe(at packageRoot: URL) throws -> SPMPackageDescription {
        // A private scratch directory, not the package's own `.build`.
        //
        // SwiftPM locks its scratch directory for the duration of a command. If
        // that directory is already locked — most obviously when describing the
        // very package a build or test run is using — the child blocks on the
        // lock and waits forever, so the CLI hangs with no output. Pointing it
        // at a directory nobody else holds removes the contention rather than
        // trying to detect it. Dependency *resolution* still reads the shared
        // package cache, so this costs no re-cloning.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-spm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "package",
            "--scratch-path", scratch.path,
            "describe", "--type", "json"
        ]
        process.currentDirectoryURL = packageRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Watchdog. The scratch path above removes the known deadlock, but a
        // subprocess can still stall for reasons outside this code — a wedged
        // toolchain, an unreachable dependency host, a lock we did not
        // anticipate. Killing it closes the pipes, which unblocks the drains
        // below and lets the timeout surface as an error the caller can report.
        //
        // `timedOut` is a Mutex, not an externally-ordered box: nothing orders
        // this one. The watchdog fires on a global queue at an arbitrary
        // moment, and `watchdog.cancel()` in the `defer` runs *after* the read
        // and cannot stop a block that is already executing — so the write
        // genuinely races the read.
        let timedOut = Mutex<Bool>(false)
        let watchdog = DispatchWorkItem {
            timedOut.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + describeTimeout, execute: watchdog)
        defer { watchdog.cancel() }

        // Drain both pipes *before* waiting on the process, and drain them
        // concurrently.
        //
        // Waiting first deadlocks as soon as the child outgrows the ~64KB pipe
        // buffer: it blocks writing into a full pipe that nobody is reading,
        // while the parent blocks waiting for a child that cannot proceed.
        // Draining them one after the other has the same failure on the second
        // pipe — filling *either* stream is enough to stall the child, so a
        // package that writes a lot of warnings to stderr would hang while the
        // parent sat reading stdout.
        // The DispatchGroup already orders this write before the read after
        // `group.wait()`. The Mutex costs one uncontended lock and lets the
        // compiler verify what was previously an `@unchecked` promise.
        let stderrData = Mutex<Data>(Data())
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            stderrData.withLock { $0 = data }
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        if timedOut.withLock({ $0 }) {
            throw ReadError.timedOut(seconds: describeTimeout)
        }
        if process.terminationStatus != 0 {
            throw ReadError.swiftToolFailed(
                exitStatus: process.terminationStatus,
                stderr: String(data: stderrData.withLock({ $0 }), encoding: .utf8) ?? ""
            )
        }
        return try parse(stdout)
    }
}
