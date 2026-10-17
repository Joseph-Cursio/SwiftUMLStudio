import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `Process` drops each `..` of a relative `currentDirectoryURL` that climbs above its base, so
/// `describe(at:)` failed on `../Outer` and described the wrong package for `..` (#141). A URL
/// relative to an explicit base is the one `URL(fileURLWithPath:)` builds from the current
/// directory, so these need no `chdir`.
@Suite("describe(at:) reads the package a relative path with .. names")
struct PackageRootDotDotTests {

    struct Layout {
        let root: URL
        let outer: URL
        let inner: URL
        let run: URL
    }

    /// `<tmp>/<uuid>/Outer` declares target `Alpha`; `<tmp>/<uuid>/Outer/Inner`
    /// is a second package with target `Beta`; `<tmp>/<uuid>/run` is empty.
    static func makeLayout() throws -> Layout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dotdot-\(UUID().uuidString)", isDirectory: true)
        let outer = root.appendingPathComponent("Outer", isDirectory: true)
        let inner = outer.appendingPathComponent("Inner", isDirectory: true)
        let run = root.appendingPathComponent("run", isDirectory: true)
        for (package, target) in [(outer, "Alpha"), (inner, "Beta")] {
            let sources = package.appendingPathComponent("Sources/\(target)", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "\(package.lastPathComponent)", targets: [.target(name: "\(target)")])
            """.write(to: package.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            try "public struct \(target)Type {}"
                .write(to: sources.appendingPathComponent("\(target).swift"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        return Layout(root: root, outer: outer, inner: inner, run: run)
    }

    @Test("../Outer from a sibling directory")
    func siblingPath() throws {
        let layout = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        // What the CLI's `URL(fileURLWithPath: "../Outer")` builds when run from `run/`.
        let packageRoot = URL(fileURLWithPath: "../Outer", relativeTo: layout.run)
        #expect(FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path))
        let description = try SPMPackageReader.describe(at: packageRoot)
        #expect(description.name == "Outer")
    }

    @Test(".. from inside a nested package")
    func parentOfNestedPackage() throws {
        let layout = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let packageRoot = URL(fileURLWithPath: "..", relativeTo: layout.inner)
        #expect(packageRoot.standardizedFileURL.lastPathComponent == "Outer")
        let description = try SPMPackageReader.describe(at: packageRoot)
        #expect(description.name == "Outer")
        #expect(description.targets.map(\.name) == ["Alpha"])
    }

    @Test("control: the same directories, spelled without a leading ..")
    func controls() throws {
        let layout = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        #expect(try SPMPackageReader.describe(at: layout.outer).name == "Outer")
        for path in ["Outer", "run/../Outer"] {
            let packageRoot = URL(fileURLWithPath: path, relativeTo: layout.root)
            #expect(try SPMPackageReader.describe(at: packageRoot).name == "Outer", "\(path)")
        }
        #expect(try SPMPackageReader.describe(
            at: URL(fileURLWithPath: "../Outer", relativeTo: layout.run).standardizedFileURL
        ).name == "Outer")
        #expect(try SPMPackageReader.describe(
            at: URL(fileURLWithPath: "../Outer", relativeTo: layout.run).absoluteURL
        ).name == "Outer")
    }

    @Test("the module map already resolves .. in a relative root")
    func mapResolvesDotDot() throws {
        let layout = try Self.makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let description = try SPMPackageReader.describe(at: layout.outer)
        let relativeRoot = URL(fileURLWithPath: "../Outer", relativeTo: layout.run)
        let keys = Array(description.sourceFileToModuleMap(packageRoot: relativeRoot).keys)
        #expect(keys.count == 1)
        #expect(keys.allSatisfy { FileManager.default.fileExists(atPath: $0) }, "\(keys)")
        #expect(keys.allSatisfy { !$0.contains("..") }, "\(keys)")
    }
}
