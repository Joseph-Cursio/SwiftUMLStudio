@testable import SwiftUMLBridgeFramework
import Testing

@Suite("SequenceSVGRenderer - render")
struct SequenceSVGRendererRenderTests {

    // MARK: - Helpers

    private func makeEdge(
        callerType: String = "Controller",
        callerMethod: String = "handle",
        calleeType: String? = "Service",
        calleeMethod: String = "process",
        isAsync: Bool = false,
        isUnresolved: Bool = false
    ) -> CallEdge {
        CallEdge(
            callerType: callerType,
            callerMethod: callerMethod,
            calleeType: calleeType,
            calleeMethod: calleeMethod,
            isAsync: isAsync,
            isUnresolved: isUnresolved
        )
    }

    // MARK: - render: SVG Structure

    @Test("render produces valid SVG wrapper")
    func renderSVGWrapper() {
        let svg = SequenceSVGRenderer.render(
            traversedEdges: [], entryType: "App", entryMethod: "main"
        )
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
    }

    @Test("render includes participant boxes")
    func renderParticipantBoxes() {
        let edges = [makeEdge()]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(svg.contains("Controller"))
        #expect(svg.contains("Service"))
    }

    @Test("render includes message labels")
    func renderMessageLabels() {
        let edges = [makeEdge(calleeMethod: "fetchData")]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(svg.contains("fetchData()"))
    }

    @Test("render includes lifeline dashed lines")
    func renderLifelines() {
        let svg = SequenceSVGRenderer.render(
            traversedEdges: [], entryType: "App", entryMethod: "main"
        )
        #expect(svg.contains("stroke-dasharray"))
    }

    @Test("render includes arrow markers in defs")
    func renderArrowMarkers() {
        let svg = SequenceSVGRenderer.render(
            traversedEdges: [], entryType: "App", entryMethod: "main"
        )
        #expect(svg.contains("<defs>"))
        #expect(svg.contains("seq-arrow"))
    }

    @Test("render includes title text")
    func renderTitle() {
        let svg = SequenceSVGRenderer.render(
            traversedEdges: [], entryType: "MyApp", entryMethod: "start"
        )
        #expect(svg.contains("MyApp.start"))
    }

    // MARK: - render: Async Arrows

    @Test("async messages use open arrow marker")
    func asyncArrowMarker() {
        let edges = [makeEdge(isAsync: true)]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(svg.contains("seq-arrow-open"))
    }

    @Test("async messages use dashed line")
    func asyncDashedLine() {
        let edges = [makeEdge(isAsync: true)]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        let lines = svg.components(separatedBy: "\n")
        let messageLines = lines.filter { $0.contains("seq-arrow-open") }
        #expect(messageLines.isEmpty == false)
    }

    // MARK: - render: Unresolved Notes

    @Test("unresolved edges render as note boxes")
    func unresolvedNoteRendering() {
        let edges = [
            makeEdge(calleeType: nil, calleeMethod: "unknown", isUnresolved: true)
        ]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(svg.contains("Unresolved: unknown()"))
        #expect(svg.contains("#FFFACD"))
    }

    // MARK: - render: Self-Calls

    @Test("self-calls render as loop path")
    func selfCallLoopPath() {
        let edges = [
            makeEdge(
                callerType: "Service",
                calleeType: "Service",
                calleeMethod: "retry"
            )
        ]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Service", entryMethod: "run"
        )
        #expect(svg.contains("<path"))
        #expect(svg.contains("retry()"))
    }

    // MARK: - renderFromLayout

    @Test("renderFromLayout produces same output as render for same input")
    func renderFromLayoutConsistency() {
        let edges = [makeEdge()]
        let layout = SequenceSVGRenderer.computeLayout(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        let svgFromLayout = SequenceSVGRenderer.renderFromLayout(layout)
        let svgDirect = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Controller", entryMethod: "handle"
        )
        #expect(svgFromLayout == svgDirect)
    }

    // MARK: - XML Escaping

    @Test("escapes special characters in participant names")
    func xmlEscapingParticipants() {
        let edges = [
            makeEdge(
                callerType: "Pair<A>",
                calleeType: "Map<B>",
                calleeMethod: "get"
            )
        ]
        let svg = SequenceSVGRenderer.render(
            traversedEdges: edges, entryType: "Pair<A>", entryMethod: "run"
        )
        #expect(svg.contains("Pair&lt;A&gt;"))
        #expect(svg.contains("Map&lt;B&gt;"))
    }
}
