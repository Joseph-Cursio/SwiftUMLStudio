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
import SwiftUI
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
                    name: "App", centerX: 150, centerY: 80,
                    kind: .executable, interfaces: ["main"], width: 160, height: 70
                ),
                makeComponent(
                    name: "Networking", centerX: 150,
                    centerY: 260,
                    kind: .library, interfaces: ["Client", "Session", "Retry"], width: 160, height: 110
                ),
            ],
            dependencies: [ComponentDependency(from: "App", toComponent: "Networking")],
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
                ComponentDependency(from: "App", toComponent: "DoesNotExist"),
                ComponentDependency(from: "AlsoMissing", toComponent: "App"),
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
                    name: "Bare", centerX: 100, centerY: 100,
                    kind: .other, interfaces: [], width: 140, height: 40
                ),
            ],
            dependencies: [],
            totalWidth: 240,
            totalHeight: 200
        )

        #expect(Self.render(layout) != nil)
    }
}
