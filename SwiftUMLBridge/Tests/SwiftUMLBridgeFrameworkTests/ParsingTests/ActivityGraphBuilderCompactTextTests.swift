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
}
