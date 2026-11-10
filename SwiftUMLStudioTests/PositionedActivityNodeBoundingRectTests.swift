//  Tests for NativeActivityDiagramView — the activity diagram canvas.
//
//  No ViewInspector, deliberately. The view renders through
//  `DiagramCanvasContainer`, which is a `GeometryReader`, and ViewInspector
//  0.10.3 traps fabricating a `GeometryProxy` on macOS 27 beta — it handles 48
//  and 52 bytes, this OS reports 76. That trap kills the test process rather
//  than failing a test, so one `.inspect()` would crashloop the whole target.
//  See ViewInspectorCompatibilityTests.swift.
//
//  This view has no gestures, key handling or pure helpers to extract — every
//  line of it is layout-driven drawing behind a private `GraphicsContext`, and
//  `GraphicsContext` has no public initializer. So `ImageRenderer` is the whole
//  strategy here: it forces a real layout-and-draw pass with no traversal, and
//  the fixtures below are shaped to walk every branch of `drawNodes` and
//  `drawEdges`.

import CoreGraphics
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - boundingRect bridging

@MainActor
@Suite("PositionedActivityNode boundingRect")
struct PositionedActivityNodeBoundingRectTests {

    /// The layout engine emits center-based coordinates; Canvas draws from a
    /// top-left origin. `drawRoundedRect` and `drawBar` both rely on this.
    @Test("converts center-based coordinates to a top-left-origin rect")
    func convertsFromCenterCoordinates() {
        let node = makeNode(
            id: 0, kind: .action, centerX: 100,
            centerY: 200, label: "step", width: 80, height: 40
        )

        let rect = node.boundingRect

        #expect(rect.minX == 60)
        #expect(rect.minY == 180)
        #expect(rect.width == 80)
        #expect(rect.height == 40)
        #expect(rect.midX == 100)
        #expect(rect.midY == 200)
    }
}
