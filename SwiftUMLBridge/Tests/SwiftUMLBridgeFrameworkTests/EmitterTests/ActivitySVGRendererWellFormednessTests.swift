import Testing
@testable import SwiftUMLBridgeFramework

/// Parses `ActivitySVGRenderer` output as XML. The other `ActivitySVGRenderer` tests check
/// substrings, which a malformed document can still contain (#80).
@Suite("ActivitySVGRenderer — well-formedness")
struct ActivitySVGRendererWellFormednessTests {

    /// XML forbids these characters outright, and the renderer used to copy them into the
    /// document raw (#80).
    @Test(
        "a forbidden character in any text slot is replaced, leaving the document well-formed",
        arguments: WellFormedXML.forbiddenCharacterLabels
    )
    func forbiddenCharacterInEveryTextSlotIsReplaced(label: String) {
        // The loop body's edge runs down to the action, and its return to the loop runs back up,
        // so both the forward-edge and the back-edge label are drawn.
        let graph = ActivityGraph(
            nodes: [
                ActivityNode(id: 0, kind: .start, label: ""),
                ActivityNode(id: 1, kind: .action, label: label),
                ActivityNode(id: 2, kind: .loopStart, label: label),
                ActivityNode(id: 3, kind: .action, label: "body"),
                ActivityNode(id: 4, kind: .end, label: "")
            ],
            edges: [
                ActivityEdge(fromId: 0, toId: 1),
                ActivityEdge(fromId: 1, toId: 2),
                ActivityEdge(fromId: 2, toId: 3, label: label),
                ActivityEdge(fromId: 3, toId: 2, label: label),
                ActivityEdge(fromId: 2, toId: 4, label: "done")
            ],
            entryType: label, entryMethod: "run"
        )
        let svg = ActivitySVGRenderer.render(graph: graph)

        #expect(WellFormedXML.error(in: svg) == nil)
        // Two node labels and two edge labels, then the title.
        #expect(svg.ranges(of: ">\(label.xmlEscaped)</text>").count == 4)
        #expect(svg.contains(">\(label.xmlEscaped).run</text>"))
    }

    /// A form feed is whitespace to Swift, so `swiftc` accepts this body, and the line holding it
    /// lands inside the `forEach` call's action label (#80).
    @Test("a form-feed line inside a function body leaves the document well-formed")
    func formFeedLineInFunctionBodyIsWellFormed() throws {
        let source = """
            struct Runner {
                func run(values: [Int]) {
                    values.forEach { value in
            \u{0C}
                        print(value)
                    }
                }
            }
            """
        let graph = try #require(ActivityFlowExtractor.extract(from: source, entryType: "Runner", entryMethod: "run"))
        let script = ActivityScript(graph: graph, configuration: Configuration(format: .svg))

        #expect(script.text.contains("values.forEach"))
        #expect(WellFormedXML.error(in: script.text) == nil)
    }

    /// `swiftc` accepts a control character inside a block comment, and a comment inside an `if`
    /// condition is part of the condition's label (#80).
    @Test("a control character in a comment inside an if condition leaves the document well-formed")
    func controlCharacterInConditionCommentIsWellFormed() throws {
        let source = """
            struct Runner {
                func run(ready: Bool, armed: Bool) {
                    if ready /* \u{07} */ && armed {
                        print(ready)
                    }
                }
            }
            """
        let graph = try #require(ActivityFlowExtractor.extract(from: source, entryType: "Runner", entryMethod: "run"))
        let script = ActivityScript(graph: graph, configuration: Configuration(format: .svg))

        #expect(script.text.contains(">ready /* \u{2407} */ &amp;&amp; armed</text>"))
        #expect(WellFormedXML.error(in: script.text) == nil)
    }
}
