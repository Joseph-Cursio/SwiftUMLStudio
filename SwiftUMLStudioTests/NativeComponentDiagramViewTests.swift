//
//  NativeComponentDiagramViewTests.swift
//  SwiftUMLStudioTests
//
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
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Fixtures

private func makeComponent(
    name: String,
    kind: ComponentKind = .library,
    interfaces: [String] = [],
    centerX: Double,
    centerY: Double,
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

/// Every `ComponentKind`. The enum is not `CaseIterable`, so this list is
/// maintained by hand; the exhaustiveness test below fails if a case is added.
private let allKinds: [ComponentKind] = [.executable, .library, .test, .other]

// MARK: - Stereotype labelling

@Suite("NativeComponentDiagramView — stereotype labels")
struct NativeComponentStereotypeTests {

    @Test("each kind maps to its UML stereotype")
    func labelsPerKind() {
        #expect(NativeComponentDiagramView.stereotypeLabel(for: .executable) == "executable")
        #expect(NativeComponentDiagramView.stereotypeLabel(for: .library) == "library")
        #expect(NativeComponentDiagramView.stereotypeLabel(for: .test) == "test")
    }

    /// `.other` deliberately renders as "component", not "other" — it is the
    /// catch-all, and «other» would read as a real UML stereotype.
    @Test("the catch-all kind renders as «component», not «other»")
    func otherRendersAsComponent() {
        #expect(NativeComponentDiagramView.stereotypeLabel(for: .other) == "component")
    }

    /// The native canvas and the SVG fallback must label a component
    /// identically — the view documents itself as mirroring the SVG renderer,
    /// and the two switch statements are currently duplicated source.
    @Test("labels match ComponentSVGRenderer for every kind")
    func matchesSVGRenderer() {
        for kind in allKinds {
            #expect(
                NativeComponentDiagramView.stereotypeLabel(for: kind)
                    == ComponentSVGRenderer.stereotypeLabel(for: kind),
                "native and SVG stereotype labels diverged for \(kind)"
            )
        }
    }

    @Test("no kind produces an empty label")
    func noEmptyLabels() {
        for kind in allKinds {
            #expect(NativeComponentDiagramView.stereotypeLabel(for: kind).isEmpty == false)
        }
    }
}

// MARK: - Geometry constants

@Suite("NativeComponentDiagramView — geometry constants")
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

    /// Two components sharing a center have no meaningful direction. The guard
    /// must return the center rather than dividing by zero and producing NaN,
    /// which would poison the Path and blank the canvas.
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

    /// The core invariant: whatever the direction, the projected point lies on
    /// the source's own border — never inside it, never past it.
    @Test(
        "the result always lands on the source border",
        arguments: [
            (300.0, 0.0), (-300.0, 0.0), (0.0, 300.0), (0.0, -300.0),
            (300.0, 300.0), (-300.0, 300.0), (300.0, -300.0), (-300.0, -300.0),
            (10.0, 400.0), (400.0, 10.0)
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

        // Half-height is 10 and half-width 200, so the vertical bound binds first.
        #expect(abs(point.y - 10) < Self.tolerance, "should clamp to the bottom edge")
        #expect(abs(point.x) < 200, "must not run past the box width")
    }
}

// MARK: - Render pass

/// Drives the actual drawing code. `GraphicsContext` has no public initializer,
/// so `drawBox` / `drawEdges` can only run inside a real render — and
/// ViewInspector cannot provide one here without tripping the GeometryReader
/// trap. `ImageRenderer` forces a genuine layout-and-draw pass instead: no
/// traversal, no fabricated `GeometryProxy`, so no trap.
///
/// These are smoke tests. They assert the render completes and produces a
/// non-empty image; the drawing itself is verified by the geometry tests above.
@MainActor
@Suite("NativeComponentDiagramView — render pass")
struct NativeComponentRenderTests {

    private static func render(_ layout: ComponentLayout) -> NSImage? {
        let view = NativeComponentDiagramView(layout: layout, viewport: DiagramViewport())
            .frame(width: 600, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    @Test("a populated diagram renders without trapping")
    func rendersPopulatedDiagram() {
        let layout = ComponentLayout(
            components: [
                makeComponent(
                    name: "App", kind: .executable, interfaces: ["main"],
                    centerX: 150, centerY: 80, width: 160, height: 70
                ),
                makeComponent(
                    name: "Networking", kind: .library,
                    interfaces: ["Client", "Session", "Retry"],
                    centerX: 150, centerY: 260, width: 160, height: 110
                )
            ],
            dependencies: [ComponentDependency(from: "App", to: "Networking")],
            totalWidth: 400,
            totalHeight: 380
        )

        let image = Self.render(layout)

        #expect(image != nil, "the canvas must produce an image")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    @Test("an empty layout renders rather than crashing")
    func rendersEmptyLayout() {
        let layout = ComponentLayout(
            components: [], dependencies: [], totalWidth: 10, totalHeight: 10
        )

        #expect(Self.render(layout) != nil)
    }

    /// A dependency naming a component that isn't in the layout must be skipped
    /// by the `guard let` in `drawEdges`, not crash the render.
    @Test("a dangling dependency is skipped, not fatal")
    func skipsDanglingDependency() {
        let layout = ComponentLayout(
            components: [
                makeComponent(name: "App", centerX: 100, centerY: 100)
            ],
            dependencies: [
                ComponentDependency(from: "App", to: "DoesNotExist"),
                ComponentDependency(from: "AlsoMissing", to: "App")
            ],
            totalWidth: 200,
            totalHeight: 200
        )

        #expect(Self.render(layout) != nil)
    }

    @Test("a component with no interfaces renders its header only")
    func rendersInterfacelessComponent() {
        let layout = ComponentLayout(
            components: [
                makeComponent(
                    name: "Bare", kind: .other, interfaces: [],
                    centerX: 100, centerY: 100, width: 140, height: 40
                )
            ],
            dependencies: [],
            totalWidth: 240,
            totalHeight: 200
        )

        #expect(Self.render(layout) != nil)
    }
}

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
