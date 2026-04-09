import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("DependencyGraphGenerator")
struct DependencyGraphGeneratorTests {

    private let generator = DependencyGraphGenerator()

    // MARK: - Helper

    /// Writes `source` to a uniquely-named temp `.swift` file and returns its path.
    private func tempSwiftFile(_ source: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - Types mode: empty input

    @Test("empty paths produce empty deps script")
    func emptyPathsProduceEmptyScript() {
        let script = generator.generateScript(for: [], mode: .types)
        #expect(script.format == .plantuml)
        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("@enduml"))
    }

    // MARK: - Types mode: inheritance extraction

    @Test("class inheriting another class produces an inherits edge in PlantUML output")
    func classInheritanceEdgeAppearsInPlantUML() throws {
        let source = """
        class Animal {}
        class Dog: Animal {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(for: [path], mode: .types)
        #expect(script.text.contains("Dog"))
        #expect(script.text.contains("Animal"))
        #expect(script.text.contains("inherits"))
    }

    @Test("struct conforming to protocol produces a conforms edge")
    func structConformanceEdgeAppears() throws {
        let source = """
        protocol Printable {}
        struct Report: Printable {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(for: [path], mode: .types)
        #expect(script.text.contains("Report"))
        #expect(script.text.contains("Printable"))
        #expect(script.text.contains("conforms"))
    }

    @Test("type with no inherited types has no edge lines")
    func typeWithNoInheritedTypesHasNoEdge() throws {
        let source = """
        struct Standalone {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(for: [path], mode: .types)
        // No "-->" lines (only @startuml and @enduml)
        let arrowLines = script.text.components(separatedBy: "\n").filter { $0.contains("-->") }
        #expect(arrowLines.isEmpty)
    }

    // MARK: - Types mode: access-level filtering

    @Test("public-only configuration excludes internal types from edges")
    func publicOnlyExcludesInternalTypes() throws {
        let source = """
        protocol Pub {}
        internal struct Hidden: Pub {}
        public struct Visible: Pub {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.elements = ElementOptions(havingAccessLevel: [.public, .open])
        let script = generator.generateScript(for: [path], mode: .types, with: config)
        #expect(script.text.contains("Hidden") == false)
        #expect(script.text.contains("Visible"))
    }

    // MARK: - Modules mode

    @Test("modules mode extracts import edges")
    func modulesModeExtractsImports() throws {
        let source = """
        import Foundation
        import SwiftUI

        struct View {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let script = generator.generateScript(for: [path], mode: .modules)
        #expect(script.text.contains("Foundation"))
        #expect(script.text.contains("SwiftUI"))
        #expect(script.text.contains("imports"))
    }

    @Test("modules mode uses parent directory as source module name")
    func modulesModeUsesParentDirectoryName() throws {
        let source = "import Foundation"
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        let script = generator.generateScript(for: [path], mode: .modules)
        #expect(script.text.contains(parentDir))
    }

    // MARK: - Format

    @Test("mermaid format produces graph TD header")
    func mermaidFormatProducesGraphTD() throws {
        let source = """
        protocol Service {}
        class Impl: Service {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        var config = Configuration.default
        config.format = .mermaid
        let script = generator.generateScript(for: [path], mode: .types, with: config)
        #expect(script.text.hasPrefix("graph TD"))
    }

    // MARK: - Cycle annotation

    @Test("cyclic types are annotated in PlantUML output")
    func cyclicTypesAnnotatedInPlantUML() throws {
        // We can force a cycle via modules mode with a hand-crafted import loop
        // (type cycles are harder to produce with SourceKitten without real source)
        // Test with DependencyGraphModel directly that annotation works
        let cycleEdges = [
            DependencyEdge(from: "A", to: "B", kind: .imports),
            DependencyEdge(from: "B", to: "A", kind: .imports)
        ]
        let model = DependencyGraphModel(edges: cycleEdges)
        let script = DepsScript(model: model, configuration: .default)
        #expect(script.text.contains("CyclicDependencies") || script.text.contains("Cyclic"))
    }

    // MARK: - Exclusion patterns

    @Test("excluded type names are omitted from output")
    func excludedTypeNameOmittedFromOutput() throws {
        let source = """
        protocol Internal {}
        struct Public: Internal {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = Configuration(elements: ElementOptions(exclude: ["Internal"]))
        let script = generator.generateScript(for: [path], mode: .types, with: config)
        #expect(script.text.contains("Internal") == false)
    }

    @Test("excluded type name with wildcard pattern is omitted")
    func excludedWildcardPatternOmitted() throws {
        let source = """
        protocol InternalProtocol {}
        struct MyType: InternalProtocol {}
        """
        let path = try tempSwiftFile(source)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = Configuration(elements: ElementOptions(exclude: ["Internal*"]))
        let script = generator.generateScript(for: [path], mode: .types, with: config)
        #expect(script.text.contains("InternalProtocol") == false)
    }
}
