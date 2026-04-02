import Testing
@testable import SwiftUMLBridgeFramework
import SwiftParser
import SwiftSyntax

// MARK: - Helpers

private func build(_ source: String) -> [SyntaxStructure] {
    let sourceFile = Parser.parse(source: source)
    let builder = SyntaxStructureBuilder(viewMode: .sourceAccurate)
    builder.walk(sourceFile)
    return builder.topLevelItems
}

@Suite("SyntaxStructureBuilder — Advanced")
struct SyntaxStructureBuilderAdvancedTests {

    // MARK: - Nesting

    @Test("nested class appears in outer class substructure")
    func nestedClassInSubstructure() {
        let items = build("class Outer { class Inner {} }")
        let inner = items.first?.substructure?.first { $0.kind == .class && $0.name == "Inner" }
        #expect(inner != nil)
    }

    @Test("top-level count is 1 for nested types (not flattened by builder)")
    func nestedTypeNotHoisted() {
        let items = build("class Outer { class Inner {} }")
        #expect(items.count == 1)
        #expect(items.first?.name == "Outer")
    }

    @Test("global function outside a type is not captured")
    func globalFunctionIgnored() {
        let items = build("func topLevel() {}")
        #expect(items.isEmpty)
    }

    @Test("global variable outside a type is not captured")
    func globalVariableIgnored() {
        let items = build("var globalX: Int = 0")
        #expect(items.isEmpty)
    }

    // MARK: - Subscripts / body traversal safety

    @Test("subscript body does not leak local vars as members")
    func subscriptBodyNotTraversed() {
        let source = """
        class Foo {
            subscript(i: Int) -> String {
                let local: Int = i
                return "\\(local)"
            }
        }
        """
        let items = build(source)
        let members = items.first?.substructure ?? []
        #expect(members.allSatisfy { $0.name != "local" })
    }

    // MARK: - Actor + async/throws integration

    @Test("actor with async method → correct kind and effect specifier")
    func actorWithAsyncMethod() {
        let source = """
        actor NetworkManager {
            func fetch(url: URL) async throws -> Data { fatalError() }
        }
        """
        let items = build(source)
        #expect(items.first?.kind == .actor)
        let method = items.first?.substructure?.first { $0.kind == .functionMethodInstance }
        #expect(method?.typename == "async throws")
    }

    @Test("actor kind is .actor, not .class")
    func actorIsNotClass() {
        let items = build("actor MyActor {}")
        #expect(items.first?.kind != .class)
        #expect(items.first?.kind == .actor)
    }

    // MARK: - PlantUML integration (smoke tests)

    @Test("actor produces <<actor>> stereotype in PlantUML output")
    func actorPlantUMLStereotype() {
        let source = "actor ImageCache { var count: Int = 0 }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("ImageCache"))
        #expect(script.text.contains("actor"))
    }

    @Test("async method label appears in PlantUML output")
    func asyncMethodInPlantUML() {
        let source = "class Svc { func fetch() async {} }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("fetch"))
        #expect(script.text.contains("async"))
    }

    @Test("throws method label appears in PlantUML output")
    func throwsMethodInPlantUML() {
        let source = "class Svc { func load() throws {} }"
        let script = ClassDiagramGenerator().generateScript(for: source)
        #expect(script.text.contains("load"))
        #expect(script.text.contains("throws"))
    }

    // MARK: - Attribute extraction

    @Test("@Observable class has Observable in attributeNames")
    func observableAttribute() {
        let items = build("@Observable class Foo {}")
        #expect(items.first?.attributeNames.contains("Observable") == true)
    }

    @Test("class with multiple attributes captures all names")
    func multipleAttributes() {
        let items = build("@MainActor @Observable class Foo {}")
        let names = items.first?.attributeNames ?? []
        #expect(names.contains("Observable"))
        #expect(names.contains("MainActor"))
    }

    @Test("class with no attributes has empty attributeNames")
    func noAttributes() {
        let items = build("class Foo {}")
        #expect(items.first?.attributeNames.isEmpty == true)
    }

    // MARK: - MacroConformanceTable

    @Test("Observable macro returns Observable conformance")
    func observableConformance() {
        let result = MacroConformanceTable.syntheticConformances(for: "Observable")
        #expect(result == ["Observable"])
    }

    @Test("Model macro returns Observable and PersistentModel")
    func modelConformance() {
        let result = MacroConformanceTable.syntheticConformances(for: "Model")
        #expect(result.contains("Observable"))
        #expect(result.contains("PersistentModel"))
    }

    @Test("Unknown macro returns empty array")
    func unknownMacro() {
        let result = MacroConformanceTable.syntheticConformances(for: "SomeCustomMacro")
        #expect(result.isEmpty)
    }
}
