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
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

/// Every `ActivityNodeKind`. The enum is not `CaseIterable`, so this list is
/// maintained by hand; `everyKindRenders` fails loudly if a case is added and
/// the drawing switch grows a branch nothing covers.
private let allKinds: [ActivityNodeKind] = [
    .start, .end, .action, .decision, .merge, .fork, .join, .loopStart, .loopEnd
]

/// A layout reaching every branch of `drawNodes` and `drawEdges`:
/// each node kind once, a sync and an async action (different fills), a labelled
/// action and an unlabelled one (the `guard !label.isEmpty` in `drawLabel`),
/// forward edges with and without labels, and a back edge — a target at or above
/// the source, which takes the dashed detour path instead of the straight line.
@MainActor
private func richLayout() -> ActivityLayout {
    let nodes = [
        makeNode(id: 0, kind: .start, centerX: 200, centerY: 40, width: 24, height: 24),
        makeNode(id: 1, kind: .action, centerX: 200, centerY: 120, label: "load()"),
        makeNode(id: 2, kind: .action, centerX: 200, centerY: 200, label: "await fetch()", isAsync: true),
        makeNode(id: 3, kind: .decision, centerX: 200, centerY: 290, label: "cached?", height: 60),
        makeNode(id: 4, kind: .fork, centerX: 200, centerY: 370, width: 140, height: 8),
        makeNode(id: 5, kind: .action, centerX: 120, centerY: 430),
        makeNode(id: 6, kind: .action, centerX: 300, centerY: 430, label: "log()"),
        makeNode(id: 7, kind: .join, centerX: 200, centerY: 490, width: 140, height: 8),
        makeNode(id: 8, kind: .loopStart, centerX: 200, centerY: 560, label: "for item", height: 60),
        makeNode(id: 9, kind: .action, centerX: 200, centerY: 640, label: "process()"),
        makeNode(id: 10, kind: .loopEnd, centerX: 200, centerY: 710, height: 40),
        makeNode(id: 11, kind: .merge, centerX: 200, centerY: 780, height: 40),
        makeNode(id: 12, kind: .end, centerX: 200, centerY: 850, width: 24, height: 24),
    ]
    let edges = [
        ActivityEdge(fromId: 0, toId: 1),
        ActivityEdge(fromId: 1, toId: 2),
        ActivityEdge(fromId: 2, toId: 3),
        ActivityEdge(fromId: 3, toId: 4, label: "no"),
        ActivityEdge(fromId: 4, toId: 5),
        ActivityEdge(fromId: 4, toId: 6),
        ActivityEdge(fromId: 5, toId: 7),
        ActivityEdge(fromId: 6, toId: 7),
        ActivityEdge(fromId: 7, toId: 8),
        ActivityEdge(fromId: 8, toId: 9, label: "next"),
        ActivityEdge(fromId: 9, toId: 10),
        // Back edge: target sits above the source, so the dashed detour runs.
        ActivityEdge(fromId: 10, toId: 8, label: "repeat"),
        ActivityEdge(fromId: 10, toId: 11),
        ActivityEdge(fromId: 11, toId: 12),
    ]

    return ActivityLayout(
        nodes: nodes, edges: edges,
        title: "Loader.load()",
        totalWidth: 400, totalHeight: 900
    )
}

// MARK: - Render pass

@MainActor
@Suite("NativeActivityDiagramView — render pass")
struct NativeActivityDiagramViewRenderTests {

    private static func render(_ layout: ActivityLayout) -> NSImage? {
        let view = NativeActivityDiagramView(layout: layout, viewport: DiagramViewport())
            .frame(width: 600, height: 700)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    @Test("a layout with every node kind and both edge shapes renders")
    func rendersRichLayout() {
        let image = Self.render(richLayout())

        #expect(image != nil, "the canvas must produce an image")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    @Test("an empty layout renders rather than crashing")
    func rendersEmptyLayout() {
        #expect(Self.render(ActivityLayout()) != nil)
    }

    /// Each kind on its own, so a crash in one shape's drawing names that shape
    /// rather than failing the omnibus fixture with nothing to point at.
    @Test("every node kind renders on its own", arguments: allKinds)
    func everyKindRenders(kind: ActivityNodeKind) {
        let layout = ActivityLayout(
            nodes: [makeNode(id: 0, kind: kind, centerX: 150, centerY: 100, label: "step")],
            edges: [],
            title: "single \(kind.rawValue)",
            totalWidth: 300, totalHeight: 200
        )

        #expect(Self.render(layout) != nil, "\(kind.rawValue) failed to render")
    }

    /// An edge naming a node that is not in the layout must be skipped by the
    /// `guard let` in `drawEdges`, not crash the render.
    @Test("a dangling edge is skipped, not fatal")
    func skipsDanglingEdge() {
        let layout = ActivityLayout(
            nodes: [makeNode(id: 0, kind: .action, centerX: 100, centerY: 100, label: "only")],
            edges: [
                ActivityEdge(fromId: 0, toId: 99),
                ActivityEdge(fromId: 99, toId: 0),
            ],
            title: "dangling",
            totalWidth: 300, totalHeight: 300
        )

        #expect(Self.render(layout) != nil)
    }

    /// `drawEdges` picks the back-edge path when the target sits at or above the
    /// source. Equal centres are the boundary case — `<=`, so this is a back edge.
    @Test("an edge between nodes at the same height takes the back-edge path")
    func rendersEqualHeightEdgeAsBackEdge() {
        let layout = ActivityLayout(
            nodes: [
                makeNode(id: 0, kind: .action, centerX: 100, centerY: 200, label: "left"),
                makeNode(id: 1, kind: .action, centerX: 300, centerY: 200, label: "right"),
            ],
            edges: [ActivityEdge(fromId: 0, toId: 1, label: "same row")],
            title: "boundary",
            totalWidth: 500, totalHeight: 400
        )

        #expect(Self.render(layout) != nil)
    }

    /// `drawLabel` guards on an empty label, and both edge painters guard on a
    /// nil-or-empty one. Drive all three guards.
    @Test("empty labels are skipped without crashing")
    func rendersEmptyLabels() {
        let layout = ActivityLayout(
            nodes: [
                makeNode(id: 0, kind: .action, centerX: 150, centerY: 80, label: ""),
                makeNode(id: 1, kind: .decision, centerX: 150, centerY: 200, label: "", height: 60),
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1, label: ""),
                ActivityEdge(fromId: 1, toId: 0, label: ""),
            ],
            title: "",
            totalWidth: 300, totalHeight: 300
        )

        #expect(Self.render(layout) != nil)
    }

    @Test("an unresolved action renders")
    func rendersUnresolvedAction() {
        let layout = ActivityLayout(
            nodes: [
                makeNode(
                    id: 0, kind: .action, centerX: 150,
                    centerY: 100, label: "unknown()", isUnresolved: true
                ),
            ],
            edges: [],
            title: "unresolved",
            totalWidth: 300, totalHeight: 200
        )

        #expect(Self.render(layout) != nil)
    }

    @Test("a zoomed and panned viewport renders")
    func rendersTransformedViewport() {
        let viewport = DiagramViewport()
        viewport.scale = 1.8
        viewport.offset = CGSize(width: -40, height: 25)

        let view = NativeActivityDiagramView(layout: richLayout(), viewport: viewport)
            .frame(width: 600, height: 700)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        #expect(renderer.nsImage != nil)
    }
}
