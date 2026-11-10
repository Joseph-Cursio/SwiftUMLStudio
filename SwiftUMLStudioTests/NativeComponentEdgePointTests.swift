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

import CoreGraphics
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Edge geometry

// `@MainActor` because `boundingRect` is declared in a SwiftUI file and so is
// main-actor-isolated; the edgePoint helper itself is not.
@MainActor
@Suite("NativeComponentDiagramView — edgePoint")
struct NativeComponentEdgePointTests {

    private static let tolerance = 0.0001

    @Test("a target directly to the right exits through the right border")
    func exitsRightBorder() {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 100, height: 60)
        let target = makeComponent(name: "B", centerX: 500, centerY: 0)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)

        #expect(abs(point.x - 50) < Self.tolerance, "should sit on the right edge at +halfWidth")
        #expect(abs(point.y - 0) < Self.tolerance, "a horizontal run must not drift vertically")
    }

    @Test("a target directly below exits through the bottom border")
    func exitsBottomBorder() {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 100, height: 60)
        let target = makeComponent(name: "B", centerX: 0, centerY: 500)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)

        #expect(abs(point.x - 0) < Self.tolerance, "a vertical run must not drift horizontally")
        #expect(abs(point.y - 30) < Self.tolerance, "should sit on the bottom edge at +halfHeight")
    }

    @Test("a target directly above exits through the top border")
    func exitsTopBorder() {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 100, height: 60)
        let target = makeComponent(name: "B", centerX: 0, centerY: -500)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)

        #expect(abs(point.y + 30) < Self.tolerance)
    }

    /// Two components sharing a center have no meaningful direction, and the
    /// guard returns the source's center. The 0.001 delta floor would keep the
    /// arithmetic finite even without the guard (0 × scale is 0), so this pins
    /// the result: the center, and no NaN to poison the Path and blank the
    /// canvas.
    @Test("coincident centers return the center instead of NaN")
    func coincidentCentersAreGuarded() {
        let source = makeComponent(name: "A", centerX: 42, centerY: 17)
        let target = makeComponent(name: "B", centerX: 42, centerY: 17)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)

        #expect(point.x == 42)
        #expect(point.y == 17)
        #expect(point.x.isNaN == false)
        #expect(point.y.isNaN == false)
    }

    /// The core invariant: whatever the direction, the anchor lies on the
    /// source's own border — never inside it, never past it. Two kinds of
    /// target are exceptions, and these arguments avoid both: one at the
    /// source's center (see above), and one so close to it that the 0.001
    /// delta floor lowers the scale, which puts the point inside the box.
    @Test(
        "the result lands on the source border for targets clear of its center",
        arguments: [
            (300.0, 0.0), (-300.0, 0.0), (0.0, 300.0), (0.0, -300.0),
            (300.0, 300.0), (-300.0, 300.0), (300.0, -300.0), (-300.0, -300.0),
            (10.0, 400.0), (400.0, 10.0),
        ]
    )
    func landsOnBorder(targetX: Double, targetY: Double) {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 100, height: 60)
        let target = makeComponent(name: "B", centerX: targetX, centerY: targetY)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)
        let rect = source.boundingRect

        // On the border means flush against one of the four sides, and within
        // the rect on the other axis.
        let onVerticalSide =
            abs(point.x - rect.minX) < Self.tolerance || abs(point.x - rect.maxX) < Self.tolerance
        let onHorizontalSide =
            abs(point.y - rect.minY) < Self.tolerance || abs(point.y - rect.maxY) < Self.tolerance

        #expect(onVerticalSide || onHorizontalSide, "point \(point) is not flush with any side")
        #expect(point.x >= rect.minX - Self.tolerance && point.x <= rect.maxX + Self.tolerance)
        #expect(point.y >= rect.minY - Self.tolerance && point.y <= rect.maxY + Self.tolerance)
    }

    /// The view documents itself as mirroring `ComponentSVGRenderer.edgePoint`.
    /// If they drift, the native canvas and the exported SVG draw the same
    /// dependency arrow between different points.
    @Test(
        "matches ComponentSVGRenderer.edgePoint",
        arguments: [
            (300.0, 0.0), (0.0, 300.0), (250.0, 130.0), (-90.0, -400.0), (0.0, 0.0)
        ]
    )
    func matchesSVGRenderer(targetX: Double, targetY: Double) {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 100, height: 60)
        let target = makeComponent(name: "B", centerX: targetX, centerY: targetY)

        let native = NativeComponentDiagramView.edgePoint(from: source, towards: target)
        let (svgX, svgY) = ComponentSVGRenderer.edgePoint(from: source, towards: target)

        #expect(abs(native.x - svgX) < Self.tolerance, "x diverged: \(native.x) vs \(svgX)")
        #expect(abs(native.y - svgY) < Self.tolerance, "y diverged: \(native.y) vs \(svgY)")
    }

    @Test("a wide, short box exits through the top or bottom for a steep run")
    func respectsAspectRatio() {
        let source = makeComponent(name: "A", centerX: 0, centerY: 0, width: 400, height: 20)
        let target = makeComponent(name: "B", centerX: 20, centerY: 500)

        let point = NativeComponentDiagramView.edgePoint(from: source, towards: target)

        // The run's slope, 500 ÷ 20 = 25, is steeper than the box's diagonals,
        // 20 ÷ 400 = 0.05, so the ray reaches the bottom first.
        #expect(abs(point.y - 10) < Self.tolerance, "should exit through the bottom edge")
        #expect(abs(point.x) < 200, "must not run past the box width")
    }
}
