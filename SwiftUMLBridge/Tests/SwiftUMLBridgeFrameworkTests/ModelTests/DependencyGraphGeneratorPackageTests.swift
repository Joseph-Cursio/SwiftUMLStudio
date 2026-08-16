import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("DependencyGraphGenerator — package mode")
struct DependencyGraphGeneratorPackageTests {

    private let generator = DependencyGraphGenerator()

    // MARK: - Helpers

    private func makePackage(targets: [SPMTargetDescription]) -> SPMPackageDescription {
        SPMPackageDescription(name: "TestPkg", targets: targets)
    }

    private func target(
        _ name: String,
        kind: SPMTargetDescription.Kind = .library,
        dependencies: [String] = [],
        sources: [String] = []
    ) -> SPMTargetDescription {
        SPMTargetDescription(
            name: name, kind: kind, path: "Sources/\(name)",
            sources: sources, dependencies: dependencies
        )
    }

    // MARK: - Modules mode

    @Test("modules mode emits one edge per target_dependencies pair")
    func modulesModeEmitsTargetDependencyEdges() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["Networking", "Storage"]),
            target("Networking", dependencies: ["Storage"]),
            target("Storage")
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules
        )

        #expect(script.text.contains("App --> Networking : imports"))
        #expect(script.text.contains("App --> Storage : imports"))
        #expect(script.text.contains("Networking --> Storage : imports"))
    }

    @Test("modules mode tags each node with its SPM target kind")
    func modulesModeStereotypesNodes() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["Core"]),
            target("Core", kind: .library)
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules
        )

        #expect(script.text.contains("component \"App\" as App <<executable>>"))
        #expect(script.text.contains("component \"Core\" as Core <<library>>"))
    }

    @Test("modules mode excludes test targets and their dependencies")
    func modulesModeExcludesTestTargets() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["Core"]),
            target("Core"),
            target("AppTests", kind: .test, dependencies: ["App"])
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules
        )

        #expect(script.text.contains("AppTests") == false)
        #expect(script.text.contains("App --> Core : imports"))
    }

    @Test("modules mode preserves edges for external dependencies without a stereotype node")
    func modulesModeKeepsExternalEdgesUnstereotyped() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["ArgumentParser"])
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules
        )

        #expect(script.text.contains("App --> ArgumentParser : imports"))
        // External target is not a declared component; only App is.
        #expect(script.text.contains("component \"ArgumentParser\"") == false)
    }

    // MARK: - Types mode

    @Test("types mode tags inheritance edges with owning module")
    func typesModeTagsEdgesWithModule() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DepsPkgTests-\(UUID().uuidString)", isDirectory: true)
        let coreDir = temp.appendingPathComponent("Sources/Core")
        let netDir = temp.appendingPathComponent("Sources/Networking")
        try FileManager.default.createDirectory(at: coreDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: netDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try """
        public protocol Service {}
        """.write(to: coreDir.appendingPathComponent("Service.swift"), atomically: true, encoding: .utf8)
        try """
        public struct HTTPClient: Service {}
        """.write(to: netDir.appendingPathComponent("HTTPClient.swift"), atomically: true, encoding: .utf8)

        let package = makePackage(targets: [
            SPMTargetDescription(
                name: "Core", kind: .library, path: "Sources/Core",
                sources: ["Service.swift"], dependencies: []
            ),
            SPMTargetDescription(
                name: "Networking", kind: .library, path: "Sources/Networking",
                sources: ["HTTPClient.swift"], dependencies: ["Core"]
            )
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: temp,
            mode: .types
        )

        #expect(script.text.contains("HTTPClient --> Service : conforms"))
        #expect(script.text.contains("class \"HTTPClient\" as HTTPClient <<Networking>>"))
        #expect(script.text.contains("class \"Service\" as Service <<Core>>"))
    }

}
