import Foundation

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

    /// Run `swift package describe --type json` against the package at
    /// `packageRoot` (the directory containing `Package.swift`).
    public static func describe(at packageRoot: URL) throws -> SPMPackageDescription {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "describe", "--type", "json"]
        process.currentDirectoryURL = packageRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            throw ReadError.swiftToolFailed(
                exitStatus: process.terminationStatus,
                stderr: String(data: stderr, encoding: .utf8) ?? ""
            )
        }
        return try parse(stdout)
    }
}
