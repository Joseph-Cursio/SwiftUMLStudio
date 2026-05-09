import Testing
@testable import SwiftUMLBridgeFramework

@Suite("SourceLocation")
struct SourceLocationTests {

    @Test("stores constructor arguments")
    func storesArguments() {
        let location = SourceLocation(filePath: "/Users/me/Foo.swift", line: 12, column: 5)
        #expect(location.filePath == "/Users/me/Foo.swift")
        #expect(location.line == 12)
        #expect(location.column == 5)
    }

    @Test("two locations with the same fields are equal and hash equally")
    func equalityAndHashing() {
        let lhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        let rhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    @Test("different lines compare unequal")
    func differingLinesAreUnequal() {
        let lhs = SourceLocation(filePath: "/x.swift", line: 1, column: 1)
        let rhs = SourceLocation(filePath: "/x.swift", line: 2, column: 1)
        #expect(lhs != rhs)
    }
}

@Suite("LayoutNode.sourceLocation")
struct LayoutNodeSourceLocationTests {

    @Test("init defaults sourceLocation to nil")
    func defaultIsNil() {
        let node = LayoutNode(id: "A", label: "A")
        #expect(node.sourceLocation == nil)
    }

    @Test("init can take a sourceLocation")
    func takesArgument() {
        let location = SourceLocation(filePath: "/Foo.swift", line: 10, column: 6)
        let node = LayoutNode(id: "Foo", label: "Foo", sourceLocation: location)
        #expect(node.sourceLocation == location)
    }
}

@Suite("LayoutGraphBuilder copies sourceLocation onto nodes")
struct LayoutGraphBuilderSourceLocationTests {

    @Test("buildClassDiagram populates sourceLocation from items")
    func copiesFromItem() throws {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        item.sourceLocation = SourceLocation(filePath: "/Foo.swift", line: 7, column: 1)

        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item],
            configuration: .default
        )
        let node = try #require(graph.nodes.first)
        #expect(node.sourceLocation == SourceLocation(filePath: "/Foo.swift", line: 7, column: 1))
    }

    @Test("buildClassDiagram leaves sourceLocation nil when item has none")
    func nilWhenItemMissing() throws {
        let item = SyntaxStructure(kind: .class, name: "Foo")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item],
            configuration: .default
        )
        let node = try #require(graph.nodes.first)
        #expect(node.sourceLocation == nil)
    }

    @Test("buildDependencyGraph emits nodes with no sourceLocation")
    func dependencyGraphHasNoLocation() throws {
        let model = DependencyGraphModel(
            edges: [DependencyEdge(from: "A", to: "B", kind: .imports)]
        )
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        for node in graph.nodes {
            #expect(node.sourceLocation == nil)
        }
    }
}

@Suite("SyntaxStructureProvider stamps sourceLocation from SwiftSyntax")
struct SyntaxStructureProviderLocationTests {

    @Test("create(from:) stamps line/column from the parsed source")
    func stampsLineAndColumn() throws {
        let source = """
        import Foundation

        class Foo {}

        struct Bar {}
        """
        let structure = try #require(SyntaxStructure.create(from: source))
        let items = try #require(structure.substructure)
        let foo = try #require(items.first { $0.name == "Foo" })
        let bar = try #require(items.first { $0.name == "Bar" })

        // `class Foo` is on line 3; `Foo` starts at column 7 (after `class `).
        let fooLocation = try #require(foo.sourceLocation)
        #expect(fooLocation.line == 3)
        #expect(fooLocation.column == 7)

        // `struct Bar` is on line 5; `Bar` starts at column 8 (after `struct `).
        let barLocation = try #require(bar.sourceLocation)
        #expect(barLocation.line == 5)
        #expect(barLocation.column == 8)
    }

    @Test("in-memory parsing leaves filePath empty")
    func filePathEmptyForInMemoryParse() throws {
        let structure = try #require(SyntaxStructure.create(from: "actor Worker {}"))
        let item = try #require(structure.substructure?.first)
        let location = try #require(item.sourceLocation)
        #expect(location.filePath == "")
    }
}
