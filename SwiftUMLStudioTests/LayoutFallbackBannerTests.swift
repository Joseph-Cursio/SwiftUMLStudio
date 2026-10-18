import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

/// A script in `format` holding `layoutGraph`, as a class diagram or deps graph does.
private struct StubScript: DiagramOutputting {
    let text = ""
    let format: DiagramFormat
    let layoutGraph: LayoutGraph?
}

/// A graph the layout engine put on its grid, because of `reason`.
private func fallenBack(_ reason: String) -> LayoutGraph {
    var graph = LayoutGraph(nodes: [LayoutNode(id: "A", label: "A")])
    graph.fallbackReason = reason
    return graph
}

/// The canvas draws a fallen-back graph like any other, so the banner is the only sign that the
/// boxes are on a grid (#150).
@Suite("LayoutFallbackBanner")
@MainActor
struct LayoutFallbackBannerTests {

    @Test("an SVG layout that fell back shows its reason")
    func showsReason() {
        let script = StubScript(format: .svg, layoutGraph: fallenBack("RangeError"))
        #expect(LayoutFallbackBanner.reason(for: script, isGenerating: false) == "RangeError")
    }

    @Test("a layout dagre made shows no banner")
    func hiddenForDagreLayout() {
        let script = StubScript(format: .svg, layoutGraph: LayoutGraph())
        #expect(LayoutFallbackBanner.reason(for: script, isGenerating: false) == nil)
    }

    @Test("no banner while generating, with no script, or for a format the layout does not draw")
    func hiddenOtherwise() {
        let fallen = fallenBack("RangeError")
        #expect(LayoutFallbackBanner.reason(
            for: StubScript(format: .svg, layoutGraph: fallen), isGenerating: true) == nil)
        #expect(LayoutFallbackBanner.reason(for: nil, isGenerating: false) == nil)
        #expect(LayoutFallbackBanner.reason(
            for: StubScript(format: .mermaid, layoutGraph: fallen), isGenerating: false) == nil)
    }

    @Test("the text names the reason and says nothing was lost")
    func text() {
        let banner = LayoutFallbackBanner(reason: "RangeError: Maximum call stack size exceeded.")
        #expect(LayoutFallbackBanner.headline == "Boxes placed on a grid")
        #expect(banner.detail.contains("(RangeError: Maximum call stack size exceeded.)"))
        #expect(banner.detail.contains("every type and relationship is drawn"))
    }

    /// A real graph through the real engine: dagre lays a two-class chain out, so nothing is
    /// shown.
    @Test("a graph dagre lays out shows no banner")
    func realLayout() {
        let graph = DagreLayoutEngine.layout(LayoutGraph(
            nodes: [LayoutNode(id: "Base", label: "Base"), LayoutNode(id: "Leaf", label: "Leaf")],
            edges: [LayoutEdge(sourceId: "Leaf", targetId: "Base", style: .inheritance)]
        ))
        let script = StubScript(format: .svg, layoutGraph: graph)
        #expect(LayoutFallbackBanner.reason(for: script, isGenerating: false) == nil)
    }
}
