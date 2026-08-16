import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

/// Mermaid / Nomnoml emitter-parity tests for `deps --package`. Split out of
/// `DependencyGraphGeneratorPackageTests` to keep each suite focused; the
/// `makePackage` / `target` fixture helpers are duplicated here intentionally.
@Suite("DependencyGraphGenerator — package mode Mermaid/Nomnoml parity")
struct DependencyGraphPackageParityTests {

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

    // MARK: - Mermaid / Nomnoml parity

    @Test("modules mode renders target kind on Mermaid node labels")
    func modulesModeMermaidLabelStereotype() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["Core"]),
            target("Core", kind: .library)
        ])
        var config = Configuration.default
        config.format = .mermaid

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules,
            with: config
        )

        #expect(script.text.contains("App[\"App<br/>«executable»\"]"))
        #expect(script.text.contains("Core[\"Core<br/>«library»\"]"))
    }

    @Test("modules mode renders target kind on Nomnoml edge endpoints")
    func modulesModeNomnomlInlineStereotype() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["Core"]),
            target("Core", kind: .library)
        ])
        var config = Configuration.default
        config.format = .nomnoml

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules,
            with: config
        )

        #expect(script.text.contains("[App «executable»] --> [Core «library»]"))
    }

    @Test("modules mode leaves external dependencies unstereotyped in Mermaid")
    func modulesModeMermaidLeavesExternalsBare() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["ArgumentParser"])
        ])
        var config = Configuration.default
        config.format = .mermaid

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules,
            with: config
        )

        #expect(script.text.contains("App[\"App<br/>«executable»\"]"))
        #expect(script.text.contains("ArgumentParser[\"ArgumentParser\"]"))
    }

    @Test("modules mode leaves external dependencies unstereotyped in Nomnoml")
    func modulesModeNomnomlLeavesExternalsBare() {
        let package = makePackage(targets: [
            target("App", kind: .executable, dependencies: ["ArgumentParser"])
        ])
        var config = Configuration.default
        config.format = .nomnoml

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: URL(fileURLWithPath: "/tmp/pkg"),
            mode: .modules,
            with: config
        )

        #expect(script.text.contains("[App «executable»] --> [ArgumentParser]"))
    }

    @Test("types mode tags Mermaid nodes with owning module")
    func typesModeMermaidLabelStereotype() throws {
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
        var config = Configuration.default
        config.format = .mermaid

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: temp,
            mode: .types,
            with: config
        )

        #expect(script.text.contains("HTTPClient[\"HTTPClient<br/>«Networking»\"]"))
        #expect(script.text.contains("Service[\"Service<br/>«Core»\"]"))
    }

    @Test("types mode tags Nomnoml edge endpoints with owning module")
    func typesModeNomnomlInlineStereotype() throws {
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
        var config = Configuration.default
        config.format = .nomnoml

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: temp,
            mode: .types,
            with: config
        )

        #expect(script.text.contains(
            "[HTTPClient «Networking»] --:> [Service «Core»]"
        ))
    }

    @Test("types mode leaves toModule unset for external parent types")
    func typesModeOmitsExternalParentModule() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DepsPkgTests-\(UUID().uuidString)", isDirectory: true)
        let coreDir = temp.appendingPathComponent("Sources/Core")
        try FileManager.default.createDirectory(at: coreDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try """
        import Foundation
        public final class MyError: Error {}
        """.write(to: coreDir.appendingPathComponent("MyError.swift"), atomically: true, encoding: .utf8)

        let package = makePackage(targets: [
            SPMTargetDescription(
                name: "Core", kind: .library, path: "Sources/Core",
                sources: ["MyError.swift"], dependencies: []
            )
        ])

        let script = generator.generateScript(
            forPackage: package,
            packageRoot: temp,
            mode: .types
        )

        // Source type has a module stereotype; parent (system `Error`) does not.
        #expect(script.text.contains("class \"MyError\" as MyError <<Core>>"))
        #expect(script.text.contains("class \"Error\" as Error <<") == false)
    }
}
