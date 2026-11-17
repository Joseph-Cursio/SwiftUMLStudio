import Foundation
import SwiftUMLBridgeFramework

extension String {
    /// The package directory a `--package` path names, read against the current directory with
    /// each `..` removed by text, as `cd` reads it (#141). `describe(at:)` and the generators are
    /// both handed this one URL, so a `..` after a symlink cannot send the manifest and the source
    /// files to different directories. Throws `CLIError.packageDirectoryNotFound`, naming the
    /// path as typed, when no directory is there.
    func packageRootURL() throws -> URL {
        let root = URL(fileURLWithPath: self).absoluteURL.standardized
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw CLIError.packageDirectoryNotFound(path: self) }
        return root
    }

    /// The package a `--package` path names, described by `swift package describe` and logged,
    /// with the root URL it was read from (see `packageRootURL()`). Throws
    /// `CLIError.packageNotRead`, naming the path as typed, when the directory holds no
    /// `Package.swift` or cannot be described (#282). The manifest is looked for first because
    /// SwiftPM searches upward: from `Pkg/Sources` it described `Pkg`, whose target paths the
    /// generators then read against `Pkg/Sources`, finding no files.
    func loadedPackage() throws -> (root: URL, description: SPMPackageDescription) {
        let root = try packageRootURL()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw CLIError.packageNotRead(path: self, reason: "no Package.swift found in that directory")
        }
        let description: SPMPackageDescription
        do {
            description = try SPMPackageReader.describe(at: root)
        } catch {
            throw CLIError.packageNotRead(path: self, reason: error.localizedDescription)
        }
        BridgeLogger.shared.info(
            "Loaded SPM package '\(description.name)' with \(description.targets.count) target(s)"
        )
        return (root, description)
    }
}
