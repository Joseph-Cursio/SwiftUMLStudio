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
}
