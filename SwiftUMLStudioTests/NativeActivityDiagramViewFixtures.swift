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

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Fixtures

func makeNode(
    id: Int,
    kind: ActivityNodeKind,
    centerX: Double,
    centerY: Double,
    label: String = "",
    width: Double = 120,
    height: Double = 44,
    isAsync: Bool = false,
    isUnresolved: Bool = false
) -> PositionedActivityNode {
    PositionedActivityNode(
        id: id, kind: kind, label: label,
        centerX: centerX, centerY: centerY,
        width: width, height: height,
        isAsync: isAsync, isUnresolved: isUnresolved
    )
}
