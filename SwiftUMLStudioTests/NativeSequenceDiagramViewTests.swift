//
//  NativeSequenceDiagramViewTests.swift
//  SwiftUMLStudioTests
//
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
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Fixtures

private func makeParticipant(
    name: String,
    centerX: Double,
    topY: Double = 20,
    width: Double = 120,
    height: Double = 36,
    bottomTopY: Double = 420
) -> SequenceParticipant {
    SequenceParticipant(
        name: name, centerX: centerX, topY: topY,
        width: width, height: height, bottomTopY: bottomTopY
    )
}

private func makeMessage(
    id: Int,
    label: String,
    fromX: Double,
    toX: Double,
    posY: Double,
    isAsync: Bool = false,
    isUnresolved: Bool = false,
    noteText: String? = nil
) -> SequenceMessage {
    SequenceMessage(
        id: id, label: label, fromX: fromX, toX: toX, posY: posY,
        isAsync: isAsync, isUnresolved: isUnresolved, noteText: noteText
    )
}

/// A layout reaching every drawing branch: a left-to-right call, a
/// right-to-left return, a self-loop, an async message, an unresolved one, and
/// a message carrying a note.
@MainActor
private func richLayout() -> SequenceLayout {
    SequenceLayout(
        participants: [
            makeParticipant(name: "Caller", centerX: 100),
            makeParticipant(name: "Service", centerX: 320),
            makeParticipant(name: "Store", centerX: 540)
        ],
        messages: [
            makeMessage(id: 0, label: "fetch()", fromX: 100, toX: 320, posY: 90),
            makeMessage(id: 1, label: "load()", fromX: 320, toX: 540, posY: 140, isAsync: true),
            makeMessage(id: 2, label: "retry()", fromX: 540, toX: 540, posY: 190),
            makeMessage(id: 3, label: "result", fromX: 540, toX: 320, posY: 250),
            makeMessage(
                id: 4, label: "unknown()", fromX: 320, toX: 700, posY: 300,
                isUnresolved: true
            ),
            makeMessage(
                id: 5, label: "done()", fromX: 320, toX: 100, posY: 350,
                noteText: "cached for 5 minutes"
            )
        ],
        title: "Caller.fetch()",
        totalWidth: 700,
        totalHeight: 480,
        lifelineStartY: 56,
        lifelineEndY: 420
    )
}

// MARK: - Render pass

@MainActor
@Suite("NativeSequenceDiagramView — render pass")
struct NativeSequenceDiagramViewRenderTests {

    private static func render(
        _ layout: SequenceLayout,
        viewport: DiagramViewport
    ) -> NSImage? {
        let view = NativeSequenceDiagramView(layout: layout, viewport: viewport)
            .frame(width: 800, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    @Test("a layout with every message shape renders")
    func rendersRichLayout() {
        let image = Self.render(richLayout(), viewport: DiagramViewport())

        #expect(image != nil, "the canvas must produce an image")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    @Test("an empty layout renders rather than crashing")
    func rendersEmptyLayout() {
        #expect(Self.render(SequenceLayout(), viewport: DiagramViewport()) != nil)
    }

    /// Participants render twice — a header row at the top and a mirrored row at
    /// the bottom — so both `drawParticipantBoxes(top:)` branches run.
    @Test("participants with no messages still draw both header rows")
    func rendersParticipantsWithoutMessages() {
        let layout = SequenceLayout(
            participants: [
                makeParticipant(name: "Alone", centerX: 100)
            ],
            messages: [],
            title: "empty trace",
            totalWidth: 300, totalHeight: 480,
            lifelineStartY: 56, lifelineEndY: 420
        )

        #expect(Self.render(layout, viewport: DiagramViewport()) != nil)
    }

    /// Selection draws an accent ring the default state never draws.
    @Test("the selected participant branch renders")
    func rendersSelectedParticipant() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Service"

        #expect(Self.render(richLayout(), viewport: viewport) != nil)
    }

    @Test("a layout with no title renders")
    func rendersWithoutTitle() {
        var layout = richLayout()
        layout = SequenceLayout(
            participants: layout.participants,
            messages: layout.messages,
            title: "",
            totalWidth: layout.totalWidth,
            totalHeight: layout.totalHeight,
            lifelineStartY: layout.lifelineStartY,
            lifelineEndY: layout.lifelineEndY
        )

        #expect(Self.render(layout, viewport: DiagramViewport()) != nil)
    }

    @Test("a zoomed and panned viewport renders")
    func rendersTransformedViewport() {
        let viewport = DiagramViewport()
        viewport.scale = 0.5
        viewport.offset = CGSize(width: 30, height: -20)

        #expect(Self.render(richLayout(), viewport: viewport) != nil)
    }
}

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
            .right
        ]
    )
    func handlesEveryDirection(direction: NativeDiagramGeometry.NavigationDirection) {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Service"
        let view = makeView(richLayout(), viewport: viewport)

        #expect(view.handleArrow(direction) == .handled)
    }
}

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

        makeView(viewport).selectParticipant(at: CGPoint(x: 100, y: 38))

        #expect(viewport.selectedNodeId == "Caller")
    }

    @Test("a tap on empty canvas clears the selection")
    func tapOnEmptyCanvasClears() {
        let viewport = DiagramViewport()
        viewport.selectedNodeId = "Caller"

        makeView(viewport).selectParticipant(at: CGPoint(x: 4000, y: 4000))

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

        makeView(viewport).updateHover(.active(CGPoint(x: 4000, y: 4000)))

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
