import Testing
@testable import SwiftUMLBridgeFramework

/// `DiagramFormat.drawn` picks the builder for each format and reports the format it drew, with
/// Mermaid standing in for any format a script has no builder for (#209).
@Suite("DiagramFormat.drawn — format fallback")
struct DiagramFormatFallbackTests {

    private static func drawnWithSVG(_ format: DiagramFormat) -> DrawnDiagram<Int> {
        format.drawn(plantUML: { "plantuml" }, mermaid: { "mermaid" }, svg: { ("svg", 7) })
    }

    @Test("with an SVG builder, nomnoml alone is drawn as Mermaid", arguments: [
        (DiagramFormat.plantuml, "plantuml", DiagramFormat.plantuml, Int?.none),
        (.mermaid, "mermaid", .mermaid, nil),
        (.nomnoml, "mermaid", .mermaid, nil),
        (.svg, "svg", .svg, 7)
    ])
    func withSVGBuilder(requested: DiagramFormat, text: String, reported: DiagramFormat, layout: Int?) {
        let drawn = Self.drawnWithSVG(requested)
        #expect(drawn.text == text)
        #expect(drawn.format == reported)
        #expect(drawn.layout == layout)
    }

    @Test("without an SVG builder, nomnoml and svg are drawn as Mermaid", arguments: [
        (DiagramFormat.plantuml, "plantuml", DiagramFormat.plantuml),
        (.mermaid, "mermaid", .mermaid),
        (.nomnoml, "mermaid", .mermaid),
        (.svg, "mermaid", .mermaid)
    ])
    func withoutSVGBuilder(requested: DiagramFormat, text: String, reported: DiagramFormat) {
        let drawn = requested.drawn(plantUML: { "plantuml" }, mermaid: { "mermaid" })
        #expect(drawn.text == text)
        #expect(drawn.format == reported)
        #expect(drawn.layout == nil)
    }

    @Test("only the chosen builder runs", arguments: DiagramFormat.allCases)
    func runsOneBuilder(requested: DiagramFormat) {
        var calls = [String]()
        _ = requested.drawn(
            plantUML: { calls.append("plantuml"); return "" },
            mermaid: { calls.append("mermaid"); return "" },
            svg: { calls.append("svg"); return ("", 0) }
        )
        #expect(calls.count == 1)
    }

    @Test("sequence: nomnoml prints the Mermaid text and reports mermaid")
    func sequenceNomnomlFallsBackToMermaid() {
        func script(_ format: DiagramFormat) -> SequenceScript {
            SequenceScript(
                traversedEdges: [], entryType: "Greeter", entryMethod: "greet",
                configuration: Configuration(format: format)
            )
        }
        let nomnoml = script(.nomnoml)
        #expect(nomnoml.format == .mermaid)
        #expect(nomnoml.text == script(.mermaid).text)
        #expect(nomnoml.sequenceLayout == nil)
        #expect(script(.svg).sequenceLayout != nil)
    }
}
