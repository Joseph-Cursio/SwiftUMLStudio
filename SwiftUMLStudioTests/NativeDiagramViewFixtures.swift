//  Tests for NativeDiagramView — the class / dependency diagram canvas.
//
//  No ViewInspector here, deliberately. The view's body is a `GeometryReader`,
//  and ViewInspector 0.10.3 traps fabricating a `GeometryProxy` on macOS 27
//  beta (it handles 48 and 52 bytes; this OS reports 76). The trap kills the
//  test process rather than failing a test, so one `.inspect()` would crashloop
//  the whole target. See ViewInspectorCompatibilityTests.swift.
//
//  Instead: `ImageRenderer` forces a real layout-and-draw pass — no traversal,
//  no fabricated proxy, no trap — which exercises the Canvas drawing closure.
//  The pure geometry already lives in `NativeDiagramGeometry` and is covered by
//  NativeDiagramGeometryTests; what is covered here is the drawing itself plus
//  the keyboard-selection logic, which a render pass never fires.

import SwiftUMLBridgeFramework

// MARK: - Fixtures

func makeNode(
    id: String,
    posX: Double,
    posY: Double,
    label: String? = nil,
    stereotype: String? = nil,
    compartments: [NodeCompartment] = [],
    module: String? = nil,
    width: Double = 140,
    height: Double = 90
) -> LayoutNode {
    var node = LayoutNode(
        id: id,
        label: label ?? id,
        stereotype: stereotype,
        compartments: compartments,
        module: module
    )
    node.posX = posX
    node.posY = posY
    node.width = width
    node.height = height
    return node
}

func makeEdge(
    from source: String,
    to target: String,
    style: EdgeStyle,
    label: String? = nil,
    points: [(Double, Double)] = []
) -> LayoutEdge {
    var edge = LayoutEdge(sourceId: source, targetId: target, label: label, style: style)
    edge.points = points.map { LayoutPoint(posX: $0.0, posY: $0.1) }
    return edge
}

/// A graph that reaches every drawing branch: two modules (so clusters and
/// module stripes render), a node with both a stereotype and two compartments,
/// a bare node with neither, and one edge of every `EdgeStyle` so the
/// arrowhead, diamond and dash paths all run.
@MainActor
func richGraph() -> LayoutGraph {
    let nodes = [
        makeNode(
            id: "Client",
            posX: 120,
            posY: 100,
            stereotype: "class",
            compartments: [
                NodeCompartment(title: "Properties", items: ["session: URLSession", "retries: Int"]),
                NodeCompartment(title: "Methods", items: ["send()", "cancel()"]),
            ], module: "Networking"
        ),
        makeNode(id: "Transport", posX: 320, posY: 100, stereotype: "protocol", module: "Networking"),
        makeNode(id: "Logger", posX: 120, posY: 300, module: "Core"),
        makeNode(id: "Bare", posX: 320, posY: 300),
    ]
    let edges = [
        makeEdge(from: "Client", to: "Transport", style: .inheritance, label: "extends"),
        makeEdge(from: "Client", to: "Logger", style: .realization),
        makeEdge(from: "Transport", to: "Logger", style: .dependency, label: "uses"),
        makeEdge(from: "Logger", to: "Bare", style: .association),
        makeEdge(
            from: "Client", to: "Bare", style: .composition,
            points: [(120, 100), (220, 200), (320, 300)]
        ),
    ]

    var graph = LayoutGraph(nodes: nodes, edges: edges)
    var networking = LayoutCluster(id: "Networking", label: "Networking")
    networking.posX = 220
    networking.posY = 100
    networking.width = 340
    networking.height = 160
    var core = LayoutCluster(id: "Core", label: "Core")
    core.posX = 120
    core.posY = 300
    core.width = 200
    core.height = 140
    graph.clusters = [networking, core]
    graph.width = 500
    graph.height = 450
    return graph
}
