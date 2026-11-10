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

// MARK: - Geometry constants

@Suite("NativeComponentDiagramView — geometry constants")
@MainActor
struct NativeComponentGeometryConstantTests {

    /// The view states these "must stay in sync with `ComponentSVGRenderer`'s
    /// header/box padding so the rendered native canvas matches the layout's
    /// reported sizes". The layout is computed by the SVG renderer, so a drift
    /// here silently misplaces every interface row on the native canvas.
    @Test("header, padding and line height match the layout engine")
    func matchesLayoutEngine() {
        #expect(NativeComponentDiagramView.headerHeight == ComponentSVGRenderer.headerHeight)
        #expect(NativeComponentDiagramView.boxPadding == ComponentSVGRenderer.boxPadding)
        #expect(
            NativeComponentDiagramView.interfaceLineHeight
                == ComponentSVGRenderer.interfaceLineHeight
        )
    }
}
