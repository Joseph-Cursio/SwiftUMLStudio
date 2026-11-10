//  Tests for NativeComponentDiagramView's drawing geometry and labelling.
//
//  There are deliberately NO ViewInspector body tests here. The view renders
//  through `DiagramCanvasContainer`, which is a `GeometryReader`, and
//  ViewInspector 0.10.3 traps fabricating a `GeometryProxy` on macOS 27 beta —
//  it handles 48 and 52 bytes, this OS reports 76. That trap kills the test
//  process rather than failing a test, so a single `.inspect()` here would
//  crashloop the whole target. See ViewInspectorCompatibilityTests.swift.
//
//  Everything below therefore exercises the pure geometry and labelling helpers
//  directly, which is where the logic actually lives — the body is a thin
//  Canvas wrapper over these.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - boundingRect bridging

@MainActor
@Suite("PositionedComponent boundingRect")
struct PositionedComponentBoundingRectTests {

    /// The layout engine emits center-based coordinates; Canvas draws from a
    /// top-left origin. This conversion is what `drawBox` relies on.
    @Test("converts center-based coordinates to a top-left-origin rect")
    func convertsFromCenterCoordinates() {
        let component = makeComponent(
            name: "A", centerX: 100, centerY: 200, width: 80, height: 40
        )

        let rect = component.boundingRect

        #expect(rect.minX == 60)
        #expect(rect.minY == 180)
        #expect(rect.width == 80)
        #expect(rect.height == 40)
        #expect(rect.midX == 100)
        #expect(rect.midY == 200)
    }
}
