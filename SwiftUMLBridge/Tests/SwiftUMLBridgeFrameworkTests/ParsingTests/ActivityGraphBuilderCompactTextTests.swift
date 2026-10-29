import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityGraphBuilder.compactText")
struct ActivityGraphBuilderCompactTextTests {

    /// Swift treats each of these as whitespace or a line break. Only spaces, tabs and `\n` used to
    /// collapse, so a form feed line inside a statement put a raw U+000C in its label (#80), and a
    /// CRLF file kept its line breaks.
    @Test(
        "compactText collapses each kind of whitespace and line break into one space",
        arguments: ["\u{0B}", "\u{0C}", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", " \t\n "]
    )
    func collapsesWhitespace(separator: String) {
        #expect(ActivityGraphBuilder.compactText("\(separator)first\(separator)second\(separator)") == "first second")
    }

    /// A comment can hold a control character that is not whitespace. It stays in the label, and
    /// `xmlEscaped` draws it as a control picture in SVG.
    @Test("compactText keeps a control character that is not whitespace")
    func keepsOtherControlCharacters() {
        #expect(ActivityGraphBuilder.compactText("ready /* \u{07} */") == "ready /* \u{07} */")
    }

    // MARK: - Truncation

    /// The cap is 80 Characters, and a label at the cap is kept whole. Length 80 is the only case
    /// that notices `>=` in place of `>`: that cuts it to 78, which a second call leaves alone (#63).
    @Test("a label of 79 or 80 Characters comes back unchanged", arguments: [79, 80])
    func atOrUnderTheLimitIsUnchanged(length: Int) {
        let text = String(repeating: "a", count: length)
        #expect(ActivityGraphBuilder.compactText(text) == text)
    }

    /// The exact output pins the 77 and the `…` as well as the threshold.
    @Test("a label of 81 Characters becomes its first 77 plus an ellipsis")
    func overTheLimitIsTruncated() {
        let result = ActivityGraphBuilder.compactText(String(repeating: "a", count: 81))
        #expect(result == String(repeating: "a", count: 77) + "…")
        #expect(result.count == 78)
    }

    /// 81 Characters as written, 80 once the double space collapses to one.
    @Test("the limit is measured after whitespace collapses")
    func limitIsMeasuredAfterCollapse() {
        let text = String(repeating: "a", count: 40) + "  " + String(repeating: "b", count: 39)
        let expected = String(repeating: "a", count: 40) + " " + String(repeating: "b", count: 39)
        #expect(ActivityGraphBuilder.compactText(text) == expected)
    }

    /// A family emoji is one Character but five scalars, so it counts once toward the cap, and the
    /// cut at 77 keeps it whole.
    @Test("the limit counts Characters, not Unicode scalars")
    func limitCountsCharacters() {
        let family = "👨‍👩‍👧"
        let atTheLimit = String(repeating: "a", count: 79) + family
        #expect(ActivityGraphBuilder.compactText(atTheLimit) == atTheLimit)
        let overTheLimit = String(repeating: "a", count: 76) + family + "aaaa"
        #expect(ActivityGraphBuilder.compactText(overTheLimit) == String(repeating: "a", count: 76) + family + "…")
    }

    /// The cap is on `compactText`'s own output. Callers that add `return `, `switch ` or `for … in`
    /// around it can make a node label longer than 80.
    @Test("compactText never returns more than 80 Characters", arguments: [0, 1, 79, 80, 81, 82, 200])
    func neverLongerThanTheLimit(length: Int) {
        #expect(ActivityGraphBuilder.compactText(String(repeating: "a", count: length)).count <= 80)
    }

    /// The short lengths are the ones that catch a label gaining a `…` it should not: a second call
    /// would add another.
    @Test("compacting a compacted label changes nothing", arguments: [0, 2, 79, 80, 81, 200])
    func idempotent(length: Int) {
        let once = ActivityGraphBuilder.compactText(String(repeating: "a", count: length))
        #expect(ActivityGraphBuilder.compactText(once) == once)
    }

    // MARK: - In the extracted graph

    @Test("a long statement's action label is truncated")
    func longStatementLabelIsTruncated() {
        let statement = "let veryLongVariableNameNumberOne = "
            + "someFunctionWithAVeryLongName(argumentOne: 1, argumentTwo: 2, argumentThree: 3)"
        let graph = ActivityExtractionFixture.extract("""
        struct Foo {
            func run() {
                \(statement)
            }
        }
        """)
        #expect(ActivityExtractionFixture.labels(of: .action, in: graph) == [
            "let veryLongVariableNameNumberOne = someFunctionWithAVeryLongName(argumentOne…"
        ])
    }

    /// Each line break becomes a space, which leaves one inside each parenthesis. This pins today's
    /// spacing; if it should go, change it here.
    @Test("a statement split across lines becomes one line")
    func multiLineStatementBecomesOneLine() {
        let graph = ActivityExtractionFixture.extract("""
        struct Foo {
            func run() {
                let total = compute(
                    first: 1,
                    second: 2
                )
            }
        }
        """)
        #expect(ActivityExtractionFixture.labels(of: .action, in: graph) == [
            "let total = compute( first: 1, second: 2 )"
        ])
    }
}
