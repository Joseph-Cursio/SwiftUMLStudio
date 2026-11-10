//  Tests for NativeSequenceDiagramView — the sequence diagram canvas.
//
//  No ViewInspector here, deliberately: the body is a `GeometryReader`, and
//  ViewInspector 0.10.3 traps fabricating a `GeometryProxy` on macOS 27 beta,
//  killing the test process rather than failing a test. See the fuller note in
//  NativeDiagramViewTests.swift.
//
//  `ImageRenderer` drives a real draw pass instead. The pure geometry lives in
//  `NativeSequenceGeometry` (covered by NativeSequenceGeometryTests); what is
//  covered here is the drawing itself and the keyboard-selection logic, which a
//  render pass never fires.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Pointer interaction

@MainActor
@Suite("NativeSequenceDiagramView — tap, hover and escape")
struct NativeSequenceDiagramViewPointerTests {

    private func makeView(_ viewport: DiagramViewport) -> NativeSequenceDiagramView {
        NativeSequenceDiagramView(layout: richLayout(), viewport: viewport)
    }

    /// Participant boxes render at the top of the canvas; `topY` is 20 and the
    /// box is 36 tall, so y = 38 is inside the header row.
    @Test("a tap inside a participant box selects it")
    func tapSelectsParticipant() {
        let viewport = DiagramViewport()

        makeView(viewport).select(at: CGPoint(x: 100, y: 38))

        #expect(viewport.selectedNodeId == "Caller")
    }

    @Test("a tap on empty canvas clears the selection")
    func tapOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Caller"

        makeView(viewport).select(at: CGPoint(x: 4_000, y: 4_000))

        #expect(viewport.selectedNodeId == nil)
    }

    @Test("hovering a participant sets the hovered id")
    func hoverSetsParticipant() {
        let viewport = DiagramViewport()

        makeView(viewport).updateHover(.active(CGPoint(x: 320, y: 38)))

        #expect(viewport.hoveredNodeId == "Service")
    }

    @Test("the pointer leaving clears the hovered id")
    func hoverEndedClears() {
        let viewport = DiagramViewport()
        viewport.hoveredNodeId = "Service"

        makeView(viewport).updateHover(.ended)

        #expect(viewport.hoveredNodeId == nil)
    }

    @Test("hovering empty canvas clears the hovered id")
    func hoverOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.hoveredNodeId = "Caller"

        makeView(viewport).updateHover(.active(CGPoint(x: 4_000, y: 4_000)))

        #expect(viewport.hoveredNodeId == nil)
    }

    @Test("escape clears the selection and reports the press handled")
    func escapeClearsSelection() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Service"

        let result = makeView(viewport).clearSelection()

        #expect(result == .handled)
        #expect(viewport.selectedNodeId == nil)
    }
}
