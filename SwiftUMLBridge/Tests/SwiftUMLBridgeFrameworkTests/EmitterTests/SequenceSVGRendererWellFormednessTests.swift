import Testing
@testable import SwiftUMLBridgeFramework

/// Parses `SequenceSVGRenderer` output as XML. The other `SequenceSVGRenderer` tests check
/// substrings, which a malformed document can still contain (#80).
@Suite("SequenceSVGRenderer — well-formedness")
struct SequenceSVGRendererWellFormednessTests {

    /// XML forbids these characters outright, and the renderer used to copy them into the
    /// document raw (#80).
    @Test(
        "a forbidden character in any text slot is replaced, leaving the document well-formed",
        arguments: WellFormedXML.forbiddenCharacterLabels
    )
    func forbiddenCharacterInEveryTextSlotIsReplaced(label: String) {
        let edges = [
            CallEdge(
                callerType: label, callerMethod: "run", calleeType: "Service", calleeMethod: label,
                isAsync: false, isUnresolved: false
            ),
            CallEdge(
                callerType: "Service", callerMethod: label, calleeType: "Service", calleeMethod: label,
                isAsync: true, isUnresolved: false
            ),
            CallEdge(
                callerType: "Service", callerMethod: label, calleeType: nil, calleeMethod: label,
                isAsync: false, isUnresolved: true
            )
        ]
        let svg = SequenceSVGRenderer.render(traversedEdges: edges, entryType: label, entryMethod: "run")
        let escaped = label.xmlEscaped

        #expect(WellFormedXML.error(in: svg) == nil)
        #expect(svg.contains(">\(escaped).run</text>"))
        // The participant's top and bottom boxes.
        #expect(svg.ranges(of: ">\(escaped)</text>").count == 2)
        // A message to another participant, and a self-call.
        #expect(svg.ranges(of: ">\(escaped)()</text>").count == 2)
        #expect(svg.contains(">Unresolved: \(escaped)()</text>"))
    }
}
