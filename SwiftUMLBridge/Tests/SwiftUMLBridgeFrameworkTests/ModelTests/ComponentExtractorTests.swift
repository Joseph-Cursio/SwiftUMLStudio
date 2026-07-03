import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ComponentExtractor")
struct ComponentExtractorTests {

    /// Build a synthetic SPMPackageDescription representing:
    ///   Networking  (library)
    ///   Persistence (library) ─ depends on Networking
    ///   App         (executable) ─ depends on Persistence + Networking
    ///   AppTests    (test) ─ depends on App
    private func makeDemoPackage() -> SPMPackageDescription {
        SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Networking", kind: .library,
                    path: "Sources/Networking",
                    sources: [], dependencies: []
                ),
                SPMTargetDescription(
                    name: "Persistence", kind: .library,
                    path: "Sources/Persistence",
                    sources: [], dependencies: ["Networking"]
                ),
                SPMTargetDescription(
                    name: "App", kind: .executable,
                    path: "Sources/App",
                    sources: [], dependencies: ["Persistence", "Networking"]
                ),
                SPMTargetDescription(
                    name: "AppTests", kind: .test,
                    path: "Tests/AppTests",
                    sources: [], dependencies: ["App"]
                )
            ]
        )
    }

    private let dummyRoot = URL(fileURLWithPath: "/tmp/demo-package-root")

    @Test("excludes test targets by default")
    func excludesTestTargets() {
        let model = ComponentExtractor.extract(
            package: makeDemoPackage(), packageRoot: dummyRoot
        )
        let names = Set(model.components.map(\.name))
        #expect(names == ["Networking", "Persistence", "App"])
    }

    @Test("includeTestTargets surfaces the test target")
    func includesTestTargetWhenAsked() {
        let model = ComponentExtractor.extract(
            package: makeDemoPackage(), packageRoot: dummyRoot,
            includeTestTargets: true
        )
        let names = Set(model.components.map(\.name))
        #expect(names == ["Networking", "Persistence", "App", "AppTests"])
    }

    @Test("dependencies mirror target_dependencies between visible components")
    func dependenciesMirrorTargetDependencies() {
        let model = ComponentExtractor.extract(
            package: makeDemoPackage(), packageRoot: dummyRoot
        )
        let edges = Set(model.dependencies.map { "\($0.from)→\($0.to)" })
        #expect(edges == ["Persistence→Networking", "App→Persistence", "App→Networking"])
    }

    @Test("dependency edges into excluded targets are pruned")
    func prunesEdgesIntoTestTargets() {
        let extras = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Lib", kind: .library, path: "Sources/Lib",
                    sources: [], dependencies: []
                ),
                SPMTargetDescription(
                    name: "Other", kind: .library, path: "Sources/Other",
                    sources: [], dependencies: ["Lib", "TestHelpers"]
                ),
                SPMTargetDescription(
                    name: "TestHelpers", kind: .test,
                    path: "Tests/TestHelpers",
                    sources: [], dependencies: []
                )
            ]
        )
        let model = ComponentExtractor.extract(package: extras, packageRoot: dummyRoot)
        let edges = Set(model.dependencies.map { "\($0.from)→\($0.to)" })
        // Only the Other → Lib edge survives; Other → TestHelpers is pruned.
        #expect(edges == ["Other→Lib"])
    }

    @Test("kind mapping preserves executable / library / test markers")
    func kindMapping() throws {
        let model = ComponentExtractor.extract(
            package: makeDemoPackage(), packageRoot: dummyRoot,
            includeTestTargets: true
        )
        let app = try #require(model.components.first { $0.name == "App" })
        let networking = try #require(model.components.first { $0.name == "Networking" })
        let appTests = try #require(model.components.first { $0.name == "AppTests" })
        #expect(app.kind == .executable)
        #expect(networking.kind == .library)
        #expect(appTests.kind == .test)
    }

    @Test("non-library/executable/test kind maps to Component.Kind.other")
    func otherKindMapping() throws {
        let package = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Plug", kind: .other, path: "Plugins/Plug",
                    sources: [], dependencies: []
                )
            ]
        )
        let model = ComponentExtractor.extract(package: package, packageRoot: dummyRoot)
        let plug = try #require(model.components.first { $0.name == "Plug" })
        #expect(plug.kind == .other)
    }

    @Test("provided interfaces list only public and open types, sorted")
    func providedInterfacesFilterAccessLevel() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("comp-test-\(UUID().uuidString)", isDirectory: true)
        let sourceDir = tempRoot.appendingPathComponent("Sources/Core", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try """
        public struct Zebra {}
        public class Apple {}
        open class Bandana {}
        struct HiddenInternal {}
        private class HiddenPrivate {}
        """.write(
            to: sourceDir.appendingPathComponent("Core.swift"),
            atomically: true, encoding: .utf8
        )

        let package = SPMPackageDescription(
            name: "Demo",
            targets: [
                SPMTargetDescription(
                    name: "Core", kind: .library, path: "Sources/Core",
                    sources: ["Core.swift"], dependencies: []
                )
            ]
        )
        let model = ComponentExtractor.extract(package: package, packageRoot: tempRoot)
        let core = try #require(model.components.first { $0.name == "Core" })
        // Only public/open types surface, alphabetically; internal and private are excluded.
        #expect(core.providedInterfaces == ["Apple", "Bandana", "Zebra"])
    }
}

@Suite("ComponentScript PlantUML emission")
struct ComponentScriptPlantUMLTests {

    @Test("emits a component block + dashed dependency arrow")
    func basicShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable, providedInterfaces: ["AppMain"])
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("component \"Networking\" as Networking <<library>>"))
        #expect(script.text.contains("component \"App\" as App <<executable>>"))
        #expect(script.text.contains("[HttpClient]"))
        #expect(script.text.contains("[AppMain]"))
        #expect(script.text.contains("App ..> Networking"))
        #expect(script.text.contains("@enduml"))
    }

    @Test("safeAlias replaces special characters")
    func safeAliasReplaces() {
        let model = ComponentModel(
            components: [
                Component(name: "swift-syntax", kind: .library),
                Component(name: "App.Main", kind: .executable)
            ],
            dependencies: [ComponentDependency(from: "App.Main", to: "swift-syntax")]
        )
        let script = ComponentScript(model: model, configuration: .default)
        #expect(script.text.contains("as swift_syntax"))
        #expect(script.text.contains("as App_Main"))
        #expect(script.text.contains("App_Main ..> swift_syntax"))
    }

    @Test("empty components emit only the @startuml/@enduml frame")
    func emptyModelPlantUML() {
        let script = ComponentScript(model: ComponentModel(), configuration: .default)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }
}

@Suite("ComponentScript Mermaid (flowchart fallback)")
struct ComponentScriptMermaidTests {

    @Test("emits flowchart TD with subgraphs and dashed arrows")
    func mermaidFlowchartShape() {
        let model = ComponentModel(
            components: [
                Component(name: "Networking", kind: .library, providedInterfaces: ["HttpClient"]),
                Component(name: "App", kind: .executable, providedInterfaces: [])
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")]
        )
        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ComponentScript(model: model, configuration: configuration)
        #expect(script.text.contains("flowchart TD"))
        #expect(script.text.contains("subgraph Networking[\"Networking\"]"))
        #expect(script.text.contains("App -.-> Networking"))
    }
}
