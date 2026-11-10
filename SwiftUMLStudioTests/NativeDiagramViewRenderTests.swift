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

import AppKit
import CoreGraphics
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
                makeEdge(from: "AlsoMissing", to: "Only", style: .association),
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
