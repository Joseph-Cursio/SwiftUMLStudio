import ArgumentParser
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
    /// with the root URL it was read from (see `packageRootURL()`).
    func loadedPackage() throws -> (root: URL, description: SPMPackageDescription) {
        let root = try packageRootURL()
        let description = try SPMPackageReader.describe(at: root)
        BridgeLogger.shared.info(
            "Loaded SPM package '\(description.name)' with \(description.targets.count) target(s)"
        )
        return (root, description)
    }
}
