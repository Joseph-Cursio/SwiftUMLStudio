//
//  NativeDiagramViewTests.swift
//  SwiftUMLStudioTests
//
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
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Fixtures

private func makeNode(
    id: String,
    label: String? = nil,
    stereotype: String? = nil,
    compartments: [NodeCompartment] = [],
    module: String? = nil,
    posX: Double,
    posY: Double,
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

private func makeEdge(
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
private func richGraph() -> LayoutGraph {
    let nodes = [
        makeNode(
            id: "Client",
            stereotype: "class",
            compartments: [
                NodeCompartment(title: "Properties", items: ["session: URLSession", "retries: Int"]),
                NodeCompartment(title: "Methods", items: ["send()", "cancel()"])
            ],
            module: "Networking",
            posX: 120, posY: 100
        ),
        makeNode(id: "Transport", stereotype: "protocol", module: "Networking", posX: 320, posY: 100),
        makeNode(id: "Logger", module: "Core", posX: 120, posY: 300),
        makeNode(id: "Bare", posX: 320, posY: 300)
    ]
    let edges = [
        makeEdge(from: "Client", to: "Transport", style: .inheritance, label: "extends"),
        makeEdge(from: "Client", to: "Logger", style: .realization),
        makeEdge(from: "Transport", to: "Logger", style: .dependency, label: "uses"),
        makeEdge(from: "Logger", to: "Bare", style: .association),
        makeEdge(
            from: "Client", to: "Bare", style: .composition,
            points: [(120, 100), (220, 200), (320, 300)]
        )
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

// MARK: - Render pass

@MainActor
@Suite("NativeDiagramView — render pass")
struct NativeDiagramViewRenderTests {

    private static func render(_ graph: LayoutGraph, viewport: DiagramViewport) -> NSImage? {
        let view = NativeDiagramView(graph: graph, viewport: viewport)
            .frame(width: 700, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    @Test("a graph with clusters, compartments and every edge style renders")
    func rendersRichGraph() {
        let image = Self.render(richGraph(), viewport: DiagramViewport())

        #expect(image != nil, "the canvas must produce an image")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    @Test("an empty graph renders rather than crashing")
    func rendersEmptyGraph() {
        #expect(Self.render(LayoutGraph(), viewport: DiagramViewport()) != nil)
    }

    /// Selection and hover take different branches in `drawNode` — a highlight
    /// fill and an accent ring that the default state never draws.
    @Test("the selected and hovered branches render")
    func rendersSelectedAndHoveredNode() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"
        viewport.hoveredNodeId = "Logger"

        #expect(Self.render(richGraph(), viewport: viewport) != nil)
    }

    /// An edge naming a node that is not in the graph must be skipped rather
    /// than crashing the render.
    @Test("a dangling edge is skipped, not fatal")
    func skipsDanglingEdge() {
        var graph = LayoutGraph(
            nodes: [makeNode(id: "Only", posX: 100, posY: 100)],
            edges: [
                makeEdge(from: "Only", to: "Missing", style: .inheritance),
                makeEdge(from: "AlsoMissing", to: "Only", style: .association)
            ]
        )
        graph.width = 300
        graph.height = 300

        #expect(Self.render(graph, viewport: DiagramViewport()) != nil)
    }

    /// A graph smaller than the viewport takes the `max(...)` branch that sizes
    /// the canvas to the available space instead of the content.
    @Test("a graph smaller than the viewport still renders")
    func rendersUndersizedGraph() {
        var graph = LayoutGraph(nodes: [makeNode(id: "Tiny", posX: 10, posY: 10, width: 20, height: 20)])
        graph.width = 30
        graph.height = 30

        #expect(Self.render(graph, viewport: DiagramViewport()) != nil)
    }

    @Test("a zoomed and panned viewport renders")
    func rendersTransformedViewport() {
        let viewport = DiagramViewport()
        viewport.scale = 2.5
        viewport.offset = CGSize(width: -80, height: 40)

        #expect(Self.render(richGraph(), viewport: viewport) != nil)
    }
}

// MARK: - Keyboard selection

@MainActor
@Suite("NativeDiagramView — arrow-key selection")
struct NativeDiagramViewArrowKeyTests {

    private func makeView(_ graph: LayoutGraph, viewport: DiagramViewport) -> NativeDiagramView {
        NativeDiagramView(graph: graph, viewport: viewport)
    }

    /// With nothing selected, the first arrow press seeds the selection rather
    /// than doing nothing — otherwise keyboard users cannot get started.
    @Test("the first arrow press with no selection selects a node")
    func seedsSelection() {
        let viewport = DiagramViewport()
        let view = makeView(richGraph(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId != nil)
    }

    @Test("an arrow press moves the selection to the neighbour in that direction")
    func movesSelection() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"
        let view = makeView(richGraph(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId == "Transport", "Transport sits to the right of Client")
    }

    /// At the edge of the graph there is no neighbour, so the fallback re-seeds
    /// to the first node. The press is still handled — it must not fall through
    /// to the system and beep.
    @Test("an arrow with no neighbour falls back rather than being ignored")
    func fallsBackAtEdge() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Transport"
        let view = makeView(richGraph(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId != nil)
    }

    /// An empty graph has nothing to select, so the press must be ignored and
    /// passed on rather than swallowed.
    @Test("an arrow on an empty graph is ignored")
    func ignoresEmptyGraph() {
        let viewport = DiagramViewport()
        let view = makeView(LayoutGraph(), viewport: viewport)

        let result = view.handleArrow(.down)

        #expect(result == .ignored)
        #expect(viewport.selectedNodeId == nil)
    }

    @Test(
        "every direction is handled",
        arguments: [
            NativeDiagramGeometry.NavigationDirection.upward,
            .down,
            .left,
            .right
        ]
    )
    func handlesEveryDirection(direction: NativeDiagramGeometry.NavigationDirection) {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"
        let view = makeView(richGraph(), viewport: viewport)

        #expect(view.handleArrow(direction) == .handled)
    }
}

// MARK: - Pointer interaction

@MainActor
@Suite("NativeDiagramView — tap, hover and escape")
struct NativeDiagramViewPointerTests {

    private func makeView(_ viewport: DiagramViewport) -> NativeDiagramView {
        NativeDiagramView(graph: richGraph(), viewport: viewport)
    }

    @Test("a tap inside a node selects it")
    func tapSelectsNode() {
        let viewport = DiagramViewport()

        makeView(viewport).selectNode(at: CGPoint(x: 120, y: 100))

        #expect(viewport.selectedNodeId == "Client")
    }

    /// Tapping empty canvas clears rather than leaving a stale selection.
    @Test("a tap on empty canvas clears the selection")
    func tapOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"

        makeView(viewport).selectNode(at: CGPoint(x: 4000, y: 4000))

        #expect(viewport.selectedNodeId == nil)
    }

    @Test("hovering a node sets the hovered id")
    func hoverSetsNode() {
        let viewport = DiagramViewport()

        makeView(viewport).updateHover(.active(CGPoint(x: 320, y: 100)))

        #expect(viewport.hoveredNodeId == "Transport")
    }

    /// The pointer leaving the canvas must clear the highlight, or a node stays
    /// lit with the mouse elsewhere.
    @Test("the pointer leaving clears the hovered id")
    func hoverEndedClears() {
        let viewport = DiagramViewport()
        viewport.hoveredNodeId = "Transport"

        makeView(viewport).updateHover(.ended)

        #expect(viewport.hoveredNodeId == nil)
    }

    @Test("hovering empty canvas clears the hovered id")
    func hoverOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.hoveredNodeId = "Client"

        makeView(viewport).updateHover(.active(CGPoint(x: 4000, y: 4000)))

        #expect(viewport.hoveredNodeId == nil)
    }

    @Test("escape clears the selection and reports the press handled")
    func escapeClearsSelection() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"

        let result = makeView(viewport).clearSelection()

        #expect(result == .handled)
        #expect(viewport.selectedNodeId == nil)
    }
}
