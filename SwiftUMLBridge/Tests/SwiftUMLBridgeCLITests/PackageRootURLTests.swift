import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// MARK: - Package root

/// `--package` is read against the current directory with each `..` removed by text (#141).
/// `PackageRootPathTests` runs the built executable from a real working directory; these run
/// in-process, where coverage can see them, against absolute paths.
@Suite("String.packageRootURL")
struct PackageRootURLTests {

    /// A fresh directory holding `Pkg` and a symlink `lnk` to `Other/Deep`.
    private static func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-package-root-url-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("Other/Deep")
        for directory in [root.appendingPathComponent("Pkg"), deep] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("lnk"), withDestinationURL: deep)
        return root
    }

    @Test("each .. is removed by text, without following a symlink before it")
    func removesDotDotByText() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = root.appendingPathComponent("Pkg").path

        #expect(try (root.path + "/Other/../Pkg").packageRootURL().path == expected)
        #expect(try (root.path + "/lnk/../Pkg").packageRootURL().path == expected)
        #expect(try (root.path + "/Pkg/").packageRootURL().path == expected)
    }

    @Test("a missing directory is reported by the path as typed")
    func missingDirectory() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let typed = root.path + "/Pkg/../NoSuchPkg"

        #expect(throws: CLIError.self) { try typed.packageRootURL() }
        #expect(CLIError.packageDirectoryNotFound(path: typed).description == "--package \(typed): no such directory")
    }

    @Test("a file is not a package directory")
    func fileIsRejected() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Package.swift")
        try "".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: CLIError.self) { try file.path.packageRootURL() }
    }
}
