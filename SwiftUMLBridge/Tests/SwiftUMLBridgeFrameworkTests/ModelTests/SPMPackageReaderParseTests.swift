import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

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
