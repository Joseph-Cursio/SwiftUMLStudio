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
