import Testing
@testable import SwiftUMLBridgeFramework

@Suite("TypeInfo and Analysis APIs")
struct TypeInfoAndAnalysisTests {

    // MARK: - TypeInfo

    @Test("TypeInfo is created for class, struct, and enum")
    func typeInfoCreation() throws {
        let classInfo = try #require(TypeInfo(from: SyntaxStructure(kind: .class, name: "Foo")))
        let structInfo = try #require(TypeInfo(from: SyntaxStructure(kind: .struct, name: "Bar")))
        let enumInfo = try #require(TypeInfo(from: SyntaxStructure(kind: .enum, name: "Baz")))
        #expect(classInfo.name == "Foo")
        #expect(structInfo.name == "Bar")
        #expect(enumInfo.name == "Baz")
    }

    @Test("TypeInfo captures kind correctly")
    func typeInfoKind() throws {
        let info = try #require(TypeInfo(from: SyntaxStructure(kind: .class, name: "Foo")))
        #expect(info.kind == "class")
        #expect(info.name == "Foo")
    }

    @Test("TypeInfo captures struct kind")
    func typeInfoStructKind() throws {
        let info = try #require(TypeInfo(from: SyntaxStructure(kind: .struct, name: "Bar")))
        #expect(info.kind == "struct")
    }

    @Test("TypeInfo captures actor kind")
    func typeInfoActorKind() throws {
        let info = try #require(TypeInfo(from: SyntaxStructure(kind: .actor, name: "Cache")))
        #expect(info.kind == "actor")
    }

    @Test("TypeInfo returns nil for unsupported kinds")
    func typeInfoUnsupported() {
        let info = TypeInfo(from: SyntaxStructure(kind: .functionFree, name: "foo"))
        #expect(info == nil)
    }

    @Test("TypeInfo captures inherited type names")
    func typeInfoInheritance() throws {
        let parent = SyntaxStructure(name: "Codable")
        let structure = SyntaxStructure(inheritedTypes: [parent], kind: .struct, name: "Msg")
        let info = try #require(TypeInfo(from: structure))
        #expect(info.inheritedTypeNames == ["Codable"])
    }

    @Test("TypeInfo captures member count")
    func typeInfoMembers() throws {
        let member = SyntaxStructure(kind: .varInstance, name: "value")
        let structure = SyntaxStructure(kind: .class, name: "Foo", substructure: [member])
        let info = try #require(TypeInfo(from: structure))
        #expect(info.memberCount == 1)
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
