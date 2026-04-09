import Testing
@testable import SwiftUMLBridgeFramework

@Suite("LayoutGraphBuilder Tests")
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

    // MARK: - Dependency Graph

    @Test("buildDependencyGraph returns empty graph for no edges")
    func depGraphEmpty() {
        let model = DependencyGraphModel(edges: [])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
    }

    @Test("buildDependencyGraph creates nodes from edge endpoints")
    func depGraphNodes() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "ModA", to: "ModB", kind: .imports)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        #expect(graph.nodes.count == 2)
        let names = graph.nodes.map(\.label).sorted()
        #expect(names == ["ModA", "ModB"])
    }

    @Test("buildDependencyGraph maps edge kinds to correct styles")
    func depGraphEdgeStyles() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "aaa", to: "bbb", kind: .inherits),
            DependencyEdge(from: "ccc", to: "ddd", kind: .conforms),
            DependencyEdge(from: "eee", to: "fff", kind: .imports)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        #expect(graph.edges[0].style == .inheritance)
        #expect(graph.edges[1].style == .realization)
        #expect(graph.edges[2].style == .dependency)
    }

    @Test("buildDependencyGraph marks cycle nodes with warning stereotype")
    func depGraphCycleDetection() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "aaa", to: "bbb", kind: .imports),
            DependencyEdge(from: "bbb", to: "aaa", kind: .imports)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        let cycleNodes = graph.nodes.filter { $0.stereotype == "warning" }
        #expect(cycleNodes.count == 2)
    }

    @Test("buildDependencyGraph non-cycle nodes have nil stereotype")
    func depGraphNonCycleNodes() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "aaa", to: "bbb", kind: .imports)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        for node in graph.nodes {
            #expect(node.stereotype == nil)
        }
    }

    @Test("buildDependencyGraph deduplicates node names")
    func depGraphDeduplicatesNodes() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "aaa", to: "bbb", kind: .imports),
            DependencyEdge(from: "bbb", to: "ccc", kind: .imports),
            DependencyEdge(from: "aaa", to: "ccc", kind: .conforms)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        #expect(graph.nodes.count == 3)
    }

    @Test("buildDependencyGraph nodes are sorted alphabetically")
    func depGraphNodesSorted() {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "Zebra", to: "Apple", kind: .imports)
        ])
        let graph = LayoutGraphBuilder.buildDependencyGraph(from: model)
        #expect(graph.nodes[0].label == "Apple")
        #expect(graph.nodes[1].label == "Zebra")
    }

    // MARK: - Static members

    @Test("extracts static methods into compartments")
    func classDiagramStaticMethod() {
        let method = SyntaxStructure(
            accessibility: .internal,
            kind: .functionMethodStatic, name: "create"
        )
        let item = SyntaxStructure(kind: .class, name: "Factory", substructure: [method])
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [item], configuration: .default)
        let allItems = graph.nodes[0].compartments.flatMap(\.items)
        #expect(allItems.contains { $0.contains("static") && $0.contains("create") })
    }

    @Test("extracts static properties into compartments")
    func classDiagramStaticProperty() {
        let prop = SyntaxStructure(
            accessibility: .internal,
            kind: .varStatic, name: "shared", typename: "MySingleton"
        )
        let item = SyntaxStructure(kind: .class, name: "MySingleton", substructure: [prop])
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [item], configuration: .default)
        let allItems = graph.nodes[0].compartments.flatMap(\.items)
        #expect(allItems.contains { $0.contains("static") && $0.contains("shared") })
    }

    // MARK: - Nested types (composition edge)

    @Test("nested type with parent produces composition edge")
    func classDiagramNestedTypeCompositionEdge() {
        // Inner must be in Outer's substructure so populateNestedTypes sets the parent link.
        // Manually setting child.parent is overwritten by prepareItems → populateNestedTypes.
        let child = SyntaxStructure(kind: .struct, name: "Inner")
        let parent = SyntaxStructure(kind: .class, name: "Outer", substructure: [child])
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [parent], configuration: .default)
        let compositionEdges = graph.edges.filter { $0.style == .composition }
        guard !compositionEdges.isEmpty else {
            #expect(Bool(false), "Expected a composition edge but found none")
            return
        }
        #expect(compositionEdges[0].sourceId == "Outer")
        // targetId is the child's fullName ("Outer.Inner") used as node ID
        #expect(compositionEdges[0].targetId == "Outer.Inner")
    }

    // MARK: - Duplicate names (uniqueId collision)

    @Test("duplicate type names get unique IDs")
    func classDiagramDuplicateNamesGetUniqueIDs() {
        let item1 = SyntaxStructure(kind: .class, name: "Foo")
        let item2 = SyntaxStructure(kind: .struct, name: "Foo")
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [item1, item2], configuration: .default)
        #expect(graph.nodes.count == 2)
        let ids = Set(graph.nodes.map(\.id))
        #expect(ids.count == 2)
    }

    @Test("three items with the same name each get a distinct ID")
    func classDiagramThreeDuplicateNamesGetUniqueIDs() {
        let items = [
            SyntaxStructure(kind: .class, name: "Foo"),
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(kind: .enum, name: "Foo")
        ]
        let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: .default)
        #expect(graph.nodes.count == 3)
        #expect(Set(graph.nodes.map(\.id)).count == 3)
    }

    // MARK: - Enum element members

    @Test("enum case in substructure appears in node compartments")
    func classDiagramEnumElementInCompartment() {
        let enumElement = SyntaxStructure(accessibility: .internal, kind: .enumelement, name: "north")
        let enumCase = SyntaxStructure(kind: .enumcase, substructure: [enumElement])
        let item = SyntaxStructure(kind: .enum, name: "Direction", substructure: [enumCase])
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [item], configuration: .default)
        let allItems = graph.nodes[0].compartments.flatMap(\.items)
        #expect(allItems.contains { $0.contains("north") })
    }

    // MARK: - Merge extensions

    @Test("merged extension config merges extension members into parent node")
    func classDiagramMergeExtensions() {
        let config = Configuration(elements: ElementOptions(showExtensions: .merged))
        let base = SyntaxStructure(kind: .class, name: "Widget")
        let ext = SyntaxStructure(kind: .extension, name: "Widget")
        let graph = LayoutGraphBuilder.buildClassDiagram(from: [base, ext], configuration: config)
        // After merging, extensions should be collapsed; only 1 node for Widget
        #expect(graph.nodes.count == 1)
    }
}
