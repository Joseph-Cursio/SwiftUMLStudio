import Foundation

/// Parses an emitted SVG document as XML, for the well-formedness tests (#56).
///
/// A substring check cannot see a malformed document: the SVG holding `<!-- Old--Code -->`
/// contained every substring the tests looked for, and `XMLParser` still rejected the whole file.
enum WellFormedXML {

    /// Where and why `XMLParser` rejected `document`, or `nil` when it is well-formed.
    static func error(in document: String) -> String? {
        let parser = XMLParser(data: Data(document.utf8))
        guard !parser.parse() else { return nil }
        let reason = parser.parserError.map { String(describing: $0) } ?? "no error reported"
        return "line \(parser.lineNumber), column \(parser.columnNumber): \(reason)"
    }

    /// Labels that each made every SVG renderer's output malformed (#80). Most hold a character
    /// XML 1.0 forbids outright: a C0 control other than TAB, LF and CR, or U+FFFE or U+FFFF.
    /// No escape makes one legal, so `xmlEscaped` has to replace it. The first five are characters
    /// APFS accepted in a directory name. The last label puts a markup character before a
    /// combining mark, which a `Character`-based replacement does not match.
    static let forbiddenCharacterLabels = [
        "Old\u{01}Code", "Bell\u{07}", "Tab\u{0B}Vertical", "Form\u{0C}Feed", "\u{1B}[31mRed",
        "\u{00}", "Unit\u{1F}Separator", "Non\u{FFFE}character", "Non\u{FFFF}character",
        "<\u{301}a> &\u{301} \"\u{07}\""
    ]
}
