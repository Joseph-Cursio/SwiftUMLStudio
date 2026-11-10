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

import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Keyboard selection

@MainActor
@Suite("NativeSequenceDiagramView — arrow-key selection")
struct NativeSequenceDiagramViewArrowKeyTests {

    private func makeView(
        _ layout: SequenceLayout,
        viewport: DiagramViewport
    ) -> NativeSequenceDiagramView {
        NativeSequenceDiagramView(layout: layout, viewport: viewport)
    }

    @Test("the first arrow press with no selection selects a participant")
    func seedsSelection() {
        let viewport = DiagramViewport()
        let view = makeView(richLayout(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId != nil)
    }

    @Test("an arrow press moves the selection along the participant row")
    func movesSelection() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Caller"
        let view = makeView(richLayout(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId == "Service", "Service sits to the right of Caller")
    }

    /// At the end of the row there is no neighbour, so the fallback re-seeds.
    /// The press stays handled — it must not fall through and beep.
    @Test("an arrow with no neighbour falls back rather than being ignored")
    func fallsBackAtEdge() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Store"
        let view = makeView(richLayout(), viewport: viewport)

        let result = view.handleArrow(.right)

        #expect(result == .handled)
        #expect(viewport.selectedNodeId != nil)
    }

    @Test("an arrow on an empty layout is ignored")
    func ignoresEmptyLayout() {
        let viewport = DiagramViewport()
        let view = makeView(SequenceLayout(), viewport: viewport)

        let result = view.handleArrow(.left)

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
        viewport.selectedNodeId = "Service"
        let view = makeView(richLayout(), viewport: viewport)

        #expect(view.handleArrow(direction) == .handled)
    }
}
