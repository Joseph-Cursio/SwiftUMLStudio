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
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
            .right,
        ]
    )
    func handlesEveryDirection(direction: NativeDiagramGeometry.NavigationDirection) {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"
        let view = makeView(richGraph(), viewport: viewport)

        #expect(view.handleArrow(direction) == .handled)
    }
}
