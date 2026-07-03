import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

private let sampleJSON = Data("""
{
  "name": "DemoPackage",
  "targets": [
    {
      "name": "Networking",
      "type": "library",
      "path": "Sources/Networking",
      "sources": ["HttpClient.swift", "URLSession+Extensions.swift"],
      "target_dependencies": ["Core"]
    },
    {
      "name": "UI",
      "type": "library",
      "path": "Sources/UI",
      "sources": ["LoginView.swift"],
      "target_dependencies": ["Networking"]
    },
    {
      "name": "DemoPackageTests",
      "type": "test",
      "path": "Tests/DemoPackageTests",
      "sources": ["NetworkingTests.swift"],
      "target_dependencies": ["Networking"]
    }
  ]
}
""".utf8)

@Suite("SPMPackageReader.parse")
struct SPMPackageReaderParseTests {

    @Test("parses package name and target count")
    func basicShape() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        #expect(pkg.name == "DemoPackage")
        #expect(pkg.targets.count == 3)
    }

    @Test("preserves target name, kind, path, sources, and dependencies")
    func preservesTargetFields() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let networking = try #require(pkg.targets.first { $0.name == "Networking" })
        #expect(networking.kind == .library)
        #expect(networking.path == "Sources/Networking")
        #expect(networking.sources == ["HttpClient.swift", "URLSession+Extensions.swift"])
        #expect(networking.dependencies == ["Core"])
    }

    @Test("recognises test targets")
    func recognisesTestTarget() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let tests = try #require(pkg.targets.first { $0.name == "DemoPackageTests" })
        #expect(tests.kind == .test)
    }

    @Test("malformed JSON throws ReadError.malformedJSON")
    func malformedThrows() {
        let bad = Data("not json".utf8)
        #expect(throws: SPMPackageReader.ReadError.self) {
            try SPMPackageReader.parse(bad)
        }
    }

    @Test("unknown target type maps to .other")
    func unknownTypeMapsToOther() throws {
        let weird = Data("""
        { "name": "X", "targets": [
          { "name": "Plug", "type": "plugin", "path": "Plugins/Plug",
            "sources": ["main.swift"], "target_dependencies": [] }
        ]}
        """.utf8)
        let pkg = try SPMPackageReader.parse(weird)
        #expect(pkg.targets.first?.kind == .other)
    }

    @Test("valid JSON object without 'name' throws malformedJSON")
    func missingNameThrows() {
        let noName = Data(#"{ "targets": [] }"#.utf8)
        #expect(throws: SPMPackageReader.ReadError.self) {
            try SPMPackageReader.parse(noName)
        }
    }

    @Test("missing 'targets' key yields a package with zero targets")
    func missingTargetsKeyYieldsEmpty() throws {
        let noTargets = Data(#"{ "name": "Solo" }"#.utf8)
        let pkg = try SPMPackageReader.parse(noTargets)
        #expect(pkg.name == "Solo")
        #expect(pkg.targets.isEmpty)
    }

    @Test("targets missing 'name' or 'path' are dropped")
    func dropsIncompleteTargets() throws {
        let json = Data(#"""
        { "name": "P", "targets": [
          { "type": "library", "path": "Sources/NoName", "sources": [], "target_dependencies": [] },
          { "name": "NoPath", "type": "library", "sources": [], "target_dependencies": [] },
          { "name": "Good", "type": "library", "path": "Sources/Good",
            "sources": ["A.swift"], "target_dependencies": [] }
        ]}
        """#.utf8)
        let pkg = try SPMPackageReader.parse(json)
        #expect(pkg.targets.map(\.name) == ["Good"])
    }

    @Test("targets without 'sources' or 'target_dependencies' default to empty arrays")
    func defaultsEmptyArrays() throws {
        let json = Data(#"""
        { "name": "P", "targets": [
          { "name": "Bare", "type": "library", "path": "Sources/Bare" }
        ]}
        """#.utf8)
        let pkg = try SPMPackageReader.parse(json)
        let bare = try #require(pkg.targets.first)
        #expect(bare.sources.isEmpty)
        #expect(bare.dependencies.isEmpty)
    }
}

@Suite("SPMPackageReader.describe")
struct SPMPackageReaderDescribeTests {

    @Test("describe(at:) on a directory without a manifest throws swiftToolFailed")
    func describeFailsWithoutManifest() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        #expect(throws: SPMPackageReader.ReadError.self) {
            _ = try SPMPackageReader.describe(at: tempRoot)
        }
    }
}

@Suite("SPMPackageDescription.sourceFileToModuleMap")
struct SPMPackageDescriptionMapTests {

    @Test("joins target.path + each source path under packageRoot")
    func joinsPaths() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let root = URL(fileURLWithPath: "/Users/me/DemoPackage")
        let map = pkg.sourceFileToModuleMap(packageRoot: root)
        #expect(map["/Users/me/DemoPackage/Sources/Networking/HttpClient.swift"] == "Networking")
        #expect(map["/Users/me/DemoPackage/Sources/UI/LoginView.swift"] == "UI")
    }

    @Test("excludes test targets from the map")
    func excludesTests() throws {
        let pkg = try SPMPackageReader.parse(sampleJSON)
        let root = URL(fileURLWithPath: "/Users/me/DemoPackage")
        let map = pkg.sourceFileToModuleMap(packageRoot: root)
        #expect(map["/Users/me/DemoPackage/Tests/DemoPackageTests/NetworkingTests.swift"] == nil)
    }
}

@Suite("ClassDiagramGenerator.generateScript(forPackage:)")
struct ClassDiagramGeneratorPackageTests {

    /// Build a temp directory mimicking a small SPM package, run the
    /// generator against it, and check the resulting LayoutGraph carries
    /// module info on each node.
    @Test("tags each LayoutNode with its owning target name")
    func tagsLayoutNodesWithModule() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let networkingDir = tempRoot.appendingPathComponent("Sources/Networking", isDirectory: true)
        let uiDir = tempRoot.appendingPathComponent("Sources/UI", isDirectory: true)
        try FileManager.default.createDirectory(at: networkingDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: uiDir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: networkingDir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )
        try "class LoginView {}".write(
            to: uiDir.appendingPathComponent("LoginView.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library,
                    path: "Sources/Networking",
                    sources: ["HttpClient.swift"], dependencies: []
                ),
                SPMTargetDescription(
                    name: "UI", kind: .library,
                    path: "Sources/UI",
                    sources: ["LoginView.swift"], dependencies: ["Networking"]
                )
            ]
        )

        var configuration = Configuration.default
        configuration.format = .svg
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: tempRoot,
            with: configuration,
            sdkPath: nil
        )
        let nodes = try #require(script.layoutGraph?.nodes)
        let httpClient = try #require(nodes.first { $0.label == "HttpClient" })
        let loginView = try #require(nodes.first { $0.label == "LoginView" })
        #expect(httpClient.module == "Networking")
        #expect(loginView.module == "UI")
    }

    @Test("PlantUML output includes the module name as an additional stereotype")
    func plantUMLIncludesModuleStereotype() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let dir = tempRoot.appendingPathComponent("Sources/Networking", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: dir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )

        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library,
                    path: "Sources/Networking",
                    sources: ["HttpClient.swift"], dependencies: []
                )
            ]
        )

        var configuration = Configuration.default
        configuration.format = .plantuml
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: tempRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    @Test("Mermaid output includes the module name as an additional stereotype")
    func mermaidIncludesModuleStereotype() throws {
        let (description, packageRoot) = try Self.makeSingleTargetPackage(named: "Networking")
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: packageRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    @Test("Nomnoml output includes the module name as an additional stereotype")
    func nomnomlIncludesModuleStereotype() throws {
        let (description, packageRoot) = try Self.makeSingleTargetPackage(named: "Networking")
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        var configuration = Configuration.default
        configuration.format = .nomnoml
        let script = ClassDiagramGenerator().generateScript(
            forPackage: description,
            packageRoot: packageRoot,
            with: configuration,
            sdkPath: nil
        )
        #expect(script.text.contains("<<Networking>>"))
    }

    /// Build a temp directory with a single `Sources/<target>/<target>.swift`
    /// holding a stub class declaration, plus a matching SPM description.
    private static func makeSingleTargetPackage(
        named targetName: String
    ) throws -> (SPMPackageDescription, URL) {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-test-\(UUID().uuidString)", isDirectory: true)
        let targetDir = tempRoot
            .appendingPathComponent("Sources/\(targetName)", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try "class HttpClient {}".write(
            to: targetDir.appendingPathComponent("HttpClient.swift"),
            atomically: true, encoding: .utf8
        )
        let description = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: targetName, kind: .library,
                    path: "Sources/\(targetName)",
                    sources: ["HttpClient.swift"], dependencies: []
                )
            ]
        )
        return (description, tempRoot)
    }
}
