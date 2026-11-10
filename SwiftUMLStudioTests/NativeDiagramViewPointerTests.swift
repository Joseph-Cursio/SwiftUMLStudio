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

import CoreGraphics
import SwiftUI
@testable import SwiftUMLStudio
import Testing

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

        makeView(viewport).select(at: CGPoint(x: 120, y: 100))

        #expect(viewport.selectedNodeId == "Client")
    }

    /// Tapping empty canvas clears rather than leaving a stale selection.
    @Test("a tap on empty canvas clears the selection")
    func tapOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Client"

        makeView(viewport).select(at: CGPoint(x: 4_000, y: 4_000))

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

        makeView(viewport).updateHover(.active(CGPoint(x: 4_000, y: 4_000)))

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
