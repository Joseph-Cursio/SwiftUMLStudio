import Foundation
import Testing

// `--package` runs made by the built `swiftumlbridge` executable from a chosen
// working directory, since a relative path is read against it (#141).
//
// `Process` dropped each `..` of a relative `currentDirectoryURL` that climbs
// above its base, so `--package ../Pkg` from a sibling directory failed with
// "The file “Pkg” doesn’t exist.", and `--package ..` ran `swift package
// describe` in the current directory, where SwiftPM's upward search could find
// another package. Changing this process's working directory would move every
// test running in parallel along with it, hence a subprocess.

/// The directories each test runs from or names.
private struct Layout {
    let root: URL
    /// `Pkg`, target `Core`, declaring `Engine`.
    var package: URL { root.appendingPathComponent("Pkg") }
    /// An empty sibling of `Pkg`.
    var run: URL { root.appendingPathComponent("run") }
    /// `Outer`, target `Alpha`, holding a second package, `Outer/Inner`, target `Beta`.
    var inner: URL { root.appendingPathComponent("Outer/Inner") }

    /// Writes the layout into a fresh temporary directory, plus a symlink `lnk`
    /// to `Other/Deep` beside a second `Other/Pkg`, target `Gamma`.
    static func make() throws -> Layout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-package-root-\(UUID().uuidString)")
        let layout = Layout(root: root)
        try writePackage(at: layout.package, name: "Pkg", target: "Core", type: "Engine")
        try writePackage(at: root.appendingPathComponent("Outer"), name: "Outer", target: "Alpha", type: "AlphaType")
        try writePackage(at: layout.inner, name: "Inner", target: "Beta", type: "BetaType")
        try writePackage(
            at: root.appendingPathComponent("Other/Pkg"), name: "OtherPkg", target: "Gamma", type: "GammaType"
        )
        let deep = root.appendingPathComponent("Other/Deep")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("lnk"), withDestinationURL: deep)
        try FileManager.default.createDirectory(at: layout.run, withIntermediateDirectories: true)
        return layout
    }

    private static func writePackage(at directory: URL, name: String, target: String, type: String) throws {
        let sources = directory.appendingPathComponent("Sources/\(target)")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "\(name)", targets: [.target(name: "\(target)")])
            """.write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "public struct \(type) {}"
            .write(to: sources.appendingPathComponent("\(type).swift"), atomically: true, encoding: .utf8)
    }
}

@Suite("CLI integration — a --package path is read as typed")
struct PackageRootPathTests {

    /// Each subcommand that reads `--package`, and a name its output holds only
    /// when it read `Pkg`'s target and that target's file.
    static let subcommands: [[String]] = [
        ["classdiagram", "--format", "plantuml"],
        ["deps", "--types"],
        ["deps", "--modules"],
        ["component"]
    ]

    private static func expectedName(for subcommand: [String]) -> String {
        subcommand.contains("--modules") ? "Core" : "Engine"
    }

    @Test("../Pkg from a sibling directory", arguments: subcommands)
    func siblingPath(subcommand: [String]) throws {
        let layout = try Layout.make()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        // `deps --types` draws no box for a type with no edges, so give `Engine` one.
        try "public struct Engine: Sendable {}".write(
            to: layout.package.appendingPathComponent("Sources/Core/Engine.swift"), atomically: true, encoding: .utf8
        )

        let run = try runCLI(subcommand + ["--package", "../Pkg", "--output", "consoleOnly"], in: layout.run)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains(Self.expectedName(for: subcommand)), "\(run.output)")
    }

    /// `swift package describe` searches upward for a manifest, so `..` from a
    /// plain subdirectory read the right package by accident. From a nested
    /// package it read the nested one.
    @Test(".. from inside a nested package reads the outer package")
    func parentOfNestedPackage() throws {
        let layout = try Layout.make()
        defer { try? FileManager.default.removeItem(at: layout.root) }

        let run = try runCLI(["component", "--package", "..", "--output", "consoleOnly"], in: layout.inner)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("[AlphaType]"), "\(run.output)")
        #expect(!run.output.contains("Beta"), "\(run.output)")
    }

    /// The manifest and the source files are read from one directory. A `..`
    /// after a symlink is removed by text, as `Process` and `cd` read it, so
    /// `lnk/../Pkg` is `Pkg` in both halves rather than its targets with
    /// `Other/Pkg`'s missing files.
    @Test("an absolute path with a symlink before .. reads one package")
    func symlinkBeforeDotDot() throws {
        let layout = try Layout.make()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let path = layout.root.path + "/lnk/../Pkg"

        let run = try runCLI(["component", "--package", path, "--output", "consoleOnly"], in: layout.run)

        #expect(run.status == 0, "\(run.output)")
        #expect(run.output.contains("[Engine]"), "\(run.output)")
    }

    @Test("a missing directory is named as typed")
    func missingDirectory() throws {
        let layout = try Layout.make()
        defer { try? FileManager.default.removeItem(at: layout.root) }

        let run = try runCLI(["component", "--package", "../NoSuchPkg", "--output", "consoleOnly"], in: layout.run)

        #expect(run.status != 0)
        #expect(run.output.contains("--package ../NoSuchPkg: no such directory"), "\(run.output)")
    }
}
