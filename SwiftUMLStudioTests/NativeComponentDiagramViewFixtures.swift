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

// MARK: - Fixtures

func makeComponent(
    name: String,
    centerX: Double,
    centerY: Double,
    kind: ComponentKind = .library,
    interfaces: [String] = [],
    width: Double = 100,
    height: Double = 60
) -> PositionedComponent {
    PositionedComponent(
        id: name,
        name: name,
        kind: kind,
        providedInterfaces: interfaces,
        centerX: centerX,
        centerY: centerY,
        width: width,
        height: height
    )
}
