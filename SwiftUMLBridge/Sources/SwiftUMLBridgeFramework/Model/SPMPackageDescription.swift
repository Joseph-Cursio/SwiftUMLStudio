import Foundation
import Synchronization

/// A single target inside a parsed `SPMPackageDescription`.
public struct SPMTargetDescription: Sendable, Equatable {
    public let name: String
    public let kind: Kind
    public let path: String
    public let sources: [String]
    public let dependencies: [String]
    /// Whether the target enables `MemberImportVisibility` (SE-0444), so each of its files sees
    /// the members another module's extension adds only when it imports that module itself
    /// (`ModuleLoads.loads(_:in:imports:)`, #201). `swift package describe` leaves settings out;
    /// `SPMPackageReader.describe(at:)` reads them from `swift package dump-package`.
    public let enablesMemberImportVisibility: Bool

    /// The target's kind. One shared `ComponentKind`, also used by the UML `Component` model.
    public typealias Kind = ComponentKind

    public init(
        name: String,
        kind: Kind,
        path: String,
        sources: [String],
        dependencies: [String],
        enablesMemberImportVisibility: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.path = path
        self.sources = sources
        self.dependencies = dependencies
        self.enablesMemberImportVisibility = enablesMemberImportVisibility
    }
}

/// Reads SPM package descriptions. The pure `parse` step is unit-testable;
/// `describe(at:)` shells out to `swift package describe --type json`, and to
/// `swift package dump-package` for the target settings `describe` leaves out.
public enum SPMPackageReader {
    public enum ReadError: Error, Equatable {
        case swiftToolFailed(exitStatus: Int32, stderr: String)
        case malformedJSON(String)
        /// `swift package describe` outlived `describeTimeout` and was killed.
        case timedOut(seconds: TimeInterval)
    }

    /// Parse JSON output produced by `swift package describe --type json`, with each target's
    /// `enablesMemberImportVisibility` read from `manifest`, the output of
    /// `swift package dump-package`, when given (`memberImportVisibilityTargets(inManifest:)`).
    public static func parse(_ data: Data, manifest: Data? = nil) throws -> SPMPackageDescription {
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
        let seesOnlyImported = manifest.map(memberImportVisibilityTargets(inManifest:)) ?? []
        let targets = targetDicts.compactMap { parseTarget($0, memberImportVisibility: seesOnlyImported) }
        return SPMPackageDescription(name: name, targets: targets)
    }

    /// The upcoming or experimental feature that limits a file to the extension members of the
    /// modules it imports (SE-0444).
    static let memberImportVisibility = "MemberImportVisibility"

    /// The names of the targets in `manifest`, the output of `swift package dump-package`, that
    /// enable `MemberImportVisibility` for Swift: by `enableUpcomingFeature`,
    /// `enableExperimentalFeature`, or `unsafeFlags` (`memberImportVisibility(in:defaultTraits:)`).
    /// A setting with a condition counts when it holds for the build `swift build` makes here: a
    /// debug build on macOS, with the package's default traits. Empty when `manifest` is not that
    /// JSON.
    public static func memberImportVisibilityTargets(inManifest manifest: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let targets = root["targets"] as? [[String: Any]] else { return [] }
        let defaultTraits = defaultTraits(in: root)
        return Set(targets.compactMap { target in
            guard let name = target["name"] as? String,
                  let settings = target["settings"] as? [[String: Any]],
                  memberImportVisibility(in: settings, defaultTraits: defaultTraits) else { return nil }
            return name
        })
    }

    /// The traits a dumped manifest turns on by default: those its `default` trait enables, and
    /// in turn those each of them enables, as `swift build` does.
    private static func defaultTraits(in root: [String: Any]) -> Set<String> {
        var enabledByTrait: [String: [String]] = [:]
        for trait in root["traits"] as? [[String: Any]] ?? [] {
            guard let name = trait["name"] as? String else { continue }
            enabledByTrait[name] = trait["enabledTraits"] as? [String] ?? []
        }
        var enabled: Set<String> = []
        var pending = enabledByTrait["default"] ?? []
        while let next = pending.popLast() {
            if enabled.insert(next).inserted { pending += enabledByTrait[next] ?? [] }
        }
        return enabled
    }

    /// Whether a dumped target's `settings` leave `MemberImportVisibility` on for Swift, read in
    /// order as `swift build` passes them to the compiler, so the last that turns it on or off
    /// wins: a feature setting turns it on, and in `unsafeFlags`, with any `-Xfrontend` dropped,
    /// `-enable-upcoming-feature` or `-enable-experimental-feature` before its name turns it on
    /// and `-disable-upcoming-feature` turns it off. Settings whose condition does not hold
    /// (`holds(_:defaultTraits:)`) are skipped.
    private static func memberImportVisibility(
        in settings: [[String: Any]], defaultTraits: Set<String>
    ) -> Bool {
        var isOn = false
        for setting in settings {
            guard setting["tool"] as? String == "swift", let kind = setting["kind"] as? [String: Any],
                  holds(setting["condition"] as? [String: Any], defaultTraits: defaultTraits) else { continue }
            let features = ["enableUpcomingFeature", "enableExperimentalFeature"]
            if features.contains(where: { (kind[$0] as? [String: Any])?["_0"] as? String == memberImportVisibility }) {
                isOn = true
            }
            let unsafeFlags = (kind["unsafeFlags"] as? [String: Any])?["_0"] as? [String] ?? []
            let flags = unsafeFlags.filter { $0 != "-Xfrontend" }
            for (flag, value) in zip(flags, flags.dropFirst()) where value == memberImportVisibility {
                switch flag {
                case "-enable-upcoming-feature", "-enable-experimental-feature": isOn = true
                case "-disable-upcoming-feature": isOn = false
                default: break
                }
            }
        }
        return isOn
    }

    /// Whether a dumped setting's `condition` holds for a debug build on macOS with
    /// `defaultTraits` on: each part it names must, and a list of traits holds when any of them
    /// is on. No condition always holds.
    private static func holds(_ condition: [String: Any]?, defaultTraits: Set<String>) -> Bool {
        guard let condition else { return true }
        if let platforms = condition["platformNames"] as? [String], !platforms.isEmpty,
           !platforms.contains("macos") { return false }
        if let config = condition["config"] as? String, config != "debug" { return false }
        if let traits = condition["traits"] as? [String], !traits.isEmpty,
           defaultTraits.isDisjoint(with: traits) { return false }
        return true
    }

    private static func parseTarget(
        _ dict: [String: Any], memberImportVisibility: Set<String>
    ) -> SPMTargetDescription? {
        guard let name = dict["name"] as? String,
              let path = dict["path"] as? String
        else { return nil }
        let kindString = dict["type"] as? String ?? ""
        let kind = SPMTargetDescription.Kind(rawValue: kindString) ?? .other
        let sources = (dict["sources"] as? [String]) ?? []
        let dependencies = (dict["target_dependencies"] as? [String]) ?? []
        return SPMTargetDescription(
            name: name, kind: kind, path: path,
            sources: sources, dependencies: dependencies,
            enablesMemberImportVisibility: memberImportVisibility.contains(name)
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
    /// `packageRoot` (the directory containing `Package.swift`), then
    /// `swift package dump-package` for the target settings `describe` leaves out
    /// (`SPMTargetDescription.enablesMemberImportVisibility`). When only the second fails, the
    /// targets read as enabling no setting, and a warning says so.
    ///
    /// - Throws: `ReadError.timedOut` if `describe` outlives `describeTimeout`,
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

        let described = try runSwiftPackage(["describe", "--type", "json"], at: packageRoot, scratch: scratch)
        let manifest: Data?
        do {
            manifest = try runSwiftPackage(["dump-package"], at: packageRoot, scratch: scratch)
        } catch {
            BridgeLogger.shared.warning(
                "swift package dump-package failed (\(error.localizedDescription)), "
                    + "so no target is read as enabling \(memberImportVisibility)"
            )
            manifest = nil
        }
        return try parse(described, manifest: manifest)
    }

    /// The standard output of `swift package <command>` run in `packageRoot` with `scratch` as
    /// its scratch path, killed after `describeTimeout`.
    private static func runSwiftPackage(_ command: [String], at packageRoot: URL, scratch: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "--scratch-path", scratch.path] + command
        // Absolute: the setter drops each `..` of a relative URL that climbs above its base, so
        // `../Pkg` ran in `<cwd>/Pkg` and `..` in the cwd itself, where SwiftPM's upward search
        // could find another package (#141).
        process.currentDirectoryURL = packageRoot.absoluteURL

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
                stderr: String(data: stderrData.withLock { $0 }, encoding: .utf8) ?? ""
            )
        }
        return stdout
    }
}

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

    /// Every (non-test) source file with its module, in path order: sorted with `String`'s `<`,
    /// so `Sources/Zed` comes before `Sources/app`. The package-mode class diagram and
    /// `deps --types` walk the files in this order. Walking `sourceFileToModuleMap` itself went in
    /// hash order, which Swift seeds per process and per dictionary, so the same package's diagram
    /// changed from run to run (#70). Path order is the `keys.sorted()` order that
    /// `DiagramGenerating`'s defaults and Studio use.
    func sourceFilesInPathOrder(packageRoot: URL) -> [(path: String, module: String)] {
        sourceFileToModuleMap(packageRoot: packageRoot)
            .sorted { $0.key < $1.key }
            .map { (path: $0.key, module: $0.value) }
    }
}
