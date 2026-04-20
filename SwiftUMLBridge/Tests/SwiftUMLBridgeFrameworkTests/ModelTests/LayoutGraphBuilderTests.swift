import Testing
@testable import SwiftUMLBridgeFramework

@Suite("LayoutGraphBuilder — class diagram")
struct LayoutGraphBuilderTests {

    // MARK: - Class Diagram: Empty Input

    @Test("buildClassDiagram returns empty graph for empty input")
    func classDiagramEmptyInput() {
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [], configuration: .default
        )
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
    }

    // MARK: - Class Diagram: Node Creation

    @Test("creates node for a class")
    func classDiagramClassNode() {
        let item = SyntaxStructure(kind: .class, name: "MyClass")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].label == "MyClass")
        #expect(graph.nodes[0].stereotype == "class")
    }

    @Test("creates node for a struct")
    func classDiagramStructNode() {
        let item = SyntaxStructure(kind: .struct, name: "MyStruct")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "struct")
    }

    @Test("creates node for an enum")
    func classDiagramEnumNode() {
        let item = SyntaxStructure(kind: .enum, name: "MyEnum")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "enum")
    }

    @Test("creates node for a protocol")
    func classDiagramProtocolNode() {
        let item = SyntaxStructure(kind: .protocol, name: "MyProtocol")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "protocol")
    }

    @Test("creates node for an actor")
    func classDiagramActorNode() {
        let item = SyntaxStructure(kind: .actor, name: "MyActor")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "actor")
    }

    @Test("creates node for a macro")
    func classDiagramMacroNode() {
        let item = SyntaxStructure(kind: .macro, name: "MyMacro")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "macro")
    }

    @Test("creates node for an extension")
    func classDiagramExtensionNode() {
        let item = SyntaxStructure(kind: .extension, name: "MyType")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes[0].stereotype == "extension")
    }

    @Test("skips non-processable kinds like functions and variables")
    func classDiagramSkipsNonProcessable() {
        let funcItem = SyntaxStructure(kind: .functionFree, name: "myFunc")
        let varItem = SyntaxStructure(kind: .varGlobal, name: "myVar")
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [funcItem, varItem], configuration: .default
        )
        #expect(graph.nodes.isEmpty)
    }

    @Test("skips items with no name")
    func classDiagramSkipsUnnamedItems() {
        let item = SyntaxStructure(kind: .class, name: nil)
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.isEmpty)
    }

    @Test("creates multiple nodes for multiple types")
    func classDiagramMultipleNodes() {
        let items = [
            SyntaxStructure(kind: .class, name: "ClassA"),
            SyntaxStructure(kind: .struct, name: "StructB"),
            SyntaxStructure(kind: .protocol, name: "ProtoC")
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: items, configuration: .default
        )
        #expect(graph.nodes.count == 3)
    }

    // MARK: - Class Diagram: Inheritance Edges

    @Test("creates inheritance edge for a class inheriting from another class")
    func classDiagramInheritanceEdge() {
        let parent = SyntaxStructure(kind: .class, name: "BaseClass")
        let child = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "BaseClass")],
            kind: .class, name: "ChildClass"
        )
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [parent, child], configuration: .default
        )
        #expect(graph.nodes.count == 2)
        #expect(graph.edges.count == 1)
        #expect(graph.edges[0].style == EdgeStyle.inheritance)
        #expect(graph.edges[0].targetId == "BaseClass")
    }

    @Test("removes edges referencing non-existent nodes")
    func classDiagramPrunesOrphanEdges() {
        let child = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "ExternalType")],
            kind: .class, name: "ChildClass"
        )
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [child], configuration: .default
        )
        // Edge to ExternalType should be pruned since ExternalType has no node
        #expect(graph.edges.isEmpty)
    }

    @Test("extension inheriting uses dependency edge style")
    func classDiagramExtensionEdge() {
        let proto = SyntaxStructure(kind: .protocol, name: "Codable")
        let ext = SyntaxStructure(
            inheritedTypes: [SyntaxStructure(name: "Codable")],
            kind: .extension, name: "MyType"
        )
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [proto, ext], configuration: .default
        )
        let depEdges = graph.edges.filter { $0.style == EdgeStyle.dependency }
        #expect(depEdges.isEmpty == false)
    }

    // MARK: - Class Diagram: Members

    @Test("extracts instance methods into compartments")
    func classDiagramMethods() {
        let method = SyntaxStructure(
            accessibility: .internal,
            kind: .functionMethodInstance, name: "doWork"
        )
        let item = SyntaxStructure(
            kind: .class, name: "Worker", substructure: [method]
        )
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        #expect(graph.nodes.count == 1)
        let compartments = graph.nodes[0].compartments
        let allItems = compartments.flatMap(\.items)
        #expect(allItems.contains { $0.contains("doWork") })
    }

    @Test("extracts instance properties into compartments")
    func classDiagramProperties() {
        let prop = SyntaxStructure(
            accessibility: .internal,
            kind: .varInstance, name: "count", typename: "Int"
        )
        let item = SyntaxStructure(
            kind: .class, name: "Counter", substructure: [prop]
        )
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [item], configuration: .default
        )
        let allItems = graph.nodes[0].compartments.flatMap(\.items)
        #expect(allItems.contains { $0.contains("count") && $0.contains("Int") })
    }
}
