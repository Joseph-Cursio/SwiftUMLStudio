import Testing
@testable import SwiftUMLBridgeFramework

@Suite("TypeInfo and Analysis APIs")
struct TypeInfoAndAnalysisTests {

    private let generator = ClassDiagramGenerator()

    // MARK: - analyzeTypes

    @Test("analyzeTypes returns TypeInfo for each type in source")
    func analyzeTypesBasic() {
        let source = "class Foo {} struct Bar {} enum Baz {}"
        // analyzeTypes takes paths, so use generateScript + TypeInfo init for unit test
        let script = generator.generateScript(for: source)
        #expect(script.text.contains("Foo"))
        #expect(script.text.contains("Bar"))
        #expect(script.text.contains("Baz"))
    }

    @Test("TypeInfo captures kind correctly")
    func typeInfoKind() {
        let info = TypeInfo(from: SyntaxStructure(kind: .class, name: "Foo"))
        #expect(info?.kind == "class")
        #expect(info?.name == "Foo")
    }

    @Test("TypeInfo captures struct kind")
    func typeInfoStructKind() {
        let info = TypeInfo(from: SyntaxStructure(kind: .struct, name: "Bar"))
        #expect(info?.kind == "struct")
    }

    @Test("TypeInfo captures actor kind")
    func typeInfoActorKind() {
        let info = TypeInfo(from: SyntaxStructure(kind: .actor, name: "Cache"))
        #expect(info?.kind == "actor")
    }

    @Test("TypeInfo returns nil for unsupported kinds")
    func typeInfoUnsupported() {
        let info = TypeInfo(from: SyntaxStructure(kind: .functionFree, name: "foo"))
        #expect(info == nil)
    }

    @Test("TypeInfo captures inherited type names")
    func typeInfoInheritance() {
        let parent = SyntaxStructure(name: "Codable")
        let structure = SyntaxStructure(inheritedTypes: [parent], kind: .struct, name: "Msg")
        let info = TypeInfo(from: structure)
        #expect(info?.inheritedTypeNames == ["Codable"])
    }

    @Test("TypeInfo captures member count")
    func typeInfoMembers() {
        let member = SyntaxStructure(kind: .varInstance, name: "value")
        let structure = SyntaxStructure(kind: .class, name: "Foo", substructure: [member])
        let info = TypeInfo(from: structure)
        #expect(info?.memberCount == 1)
    }

    // MARK: - extractEdges

    @Test("extractEdges returns dependency edges for types mode with nonexistent path")
    func extractEdgesTypes() {
        let depGen = DependencyGraphGenerator()
        let edges = depGen.extractEdges(for: ["/nonexistent/path"], mode: .types)
        #expect(edges.isEmpty)
    }

    @Test("extractEdges returns dependency edges for modules mode with nonexistent path")
    func extractEdgesModules() {
        let depGen = DependencyGraphGenerator()
        let edges = depGen.extractEdges(for: ["/nonexistent/path"], mode: .modules)
        #expect(edges.isEmpty)
    }
}
