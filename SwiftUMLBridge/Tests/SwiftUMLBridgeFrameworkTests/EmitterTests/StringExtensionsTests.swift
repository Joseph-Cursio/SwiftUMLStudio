import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("String+Extensions")
struct StringExtensionsTests {

    // MARK: - appendAsNewLine

    @Test("appendAsNewLine prepends a newline character")
    func appendAsNewLinePrependsNewline() {
        var str = "first"
        str.appendAsNewLine("second")
        #expect(str == "first\nsecond")
    }

    @Test("appendAsNewLine on empty string produces newline prefix")
    func appendAsNewLineOnEmpty() {
        var str = ""
        str.appendAsNewLine("content")
        #expect(str == "\ncontent")
    }

    @Test("appendAsNewLine can chain multiple appends")
    func appendAsNewLineMultiple() {
        var str = "line1"
        str.appendAsNewLine("line2")
        str.appendAsNewLine("line3")
        #expect(str == "line1\nline2\nline3")
    }

    // MARK: - removeAngleBracketsWithContent

    @Test("removeAngleBracketsWithContent removes generic notation")
    func removeAngleBracketsWithGeneric() {
        let result = "Collection<Element>".removeAngleBracketsWithContent()
        #expect(result == "Collection")
    }

    @Test("removeAngleBracketsWithContent leaves plain strings unchanged")
    func removeAngleBracketsNoGeneric() {
        let result = "MyClass".removeAngleBracketsWithContent()
        #expect(result == "MyClass")
    }

    @Test("removeAngleBracketsWithContent removes nested generics")
    func removeAngleBracketsNestedGeneric() {
        let result = "Dictionary<String, Int>".removeAngleBracketsWithContent()
        #expect(result == "Dictionary")
    }

    // MARK: - getAngleBracketsWithContent

    @Test("getAngleBracketsWithContent extracts angle bracket content")
    func getAngleBracketsExtracts() {
        let result = "Array<Element>".getAngleBracketsWithContent()
        #expect(result == "<Element>")
    }

    @Test("getAngleBracketsWithContent returns nil when no angle brackets")
    func getAngleBracketsNone() {
        let result = "MyClass".getAngleBracketsWithContent()
        #expect(result == nil)
    }

    @Test("getAngleBracketsWithContent handles multiple type params")
    func getAngleBracketsMultipleParams() {
        let result = "Dict<K, V>".getAngleBracketsWithContent()
        #expect(result == "<K, V>")
    }

    // MARK: - isMatching

    @Test("isMatching returns true for exact match")
    func isMatchingExactMatch() {
        #expect("MyClass".isMatching(searchPattern: "MyClass"))
    }

    @Test("isMatching returns false for non-match")
    func isMatchingNoMatch() {
        #expect("MyClass".isMatching(searchPattern: "OtherClass") == false)
    }

    @Test("isMatching supports * wildcard for any non-slash characters")
    func isMatchingStarWildcard() {
        #expect("MyClass".isMatching(searchPattern: "My*"))
        #expect("MyClass".isMatching(searchPattern: "*Class"))
        #expect("MyClass".isMatching(searchPattern: "*"))
    }

    @Test("isMatching supports ** wildcard for any characters")
    func isMatchingDoubleStarWildcard() {
        #expect("path/to/MyClass".isMatching(searchPattern: "**/MyClass"))
    }

    @Test("isMatching supports ? wildcard for single non-slash character")
    func isMatchingQuestionWildcard() {
        #expect("MyClass".isMatching(searchPattern: "MyClass?") == false)
        #expect("MyClas".isMatching(searchPattern: "MyCla?"))
    }

    // MARK: - glob metacharacters that are regex-special

    /// **Three characters were regex-special and glob-literal, and the escape class missed all
    /// three.** `}` produced an invalid pattern; `^` and `$` produced patterns that compile and
    /// can never match, because the translation had already added the real anchors.
    ///
    /// Each of these fails against the old implementation, and `a^b` / `a$b` fail *silently* —
    /// a valid regex matching nothing is exactly the shape a test has to state, because nothing
    /// throws.
    @Test("a glob containing a regex metacharacter matches itself", arguments: [
        "a}b", "a^b", "a$b", "a.b", "a+b", "a|b", "a(b)c", "a{b", "a\\b"
    ])
    func globMetacharacterMatchesItself(glob: String) throws {
        let pattern = glob.globPatternToRegex()
        #expect(throws: Never.self) { try NSRegularExpression(pattern: pattern, options: []) }
        #expect(glob.isMatching(searchPattern: glob), "\(glob) should match itself via \(pattern)")
    }

    /// The anchors this function adds must survive the escape pass — which is why the escape
    /// runs on `self` and the wrap comes after. Escaping the wrapped string would produce
    /// `\^…\$`, a pattern matching a literal caret.
    @Test("the added anchors are not themselves escaped")
    func addedAnchorsSurvive() {
        let pattern = "abc".globPatternToRegex()
        #expect(pattern == "^abc$")
    }

    /// `[` and `]` stay unescaped on purpose: they are glob syntax — `pathContainsGlobSyntax`
    /// lists `[` as one of the four characters that make a path a glob — and a glob character
    /// class is spelled the same way in a regex.
    @Test("a glob character class still selects its members")
    func globCharacterClassStillWorks() {
        #expect("b".isMatching(searchPattern: "[abc]"))
        #expect("d".isMatching(searchPattern: "[abc]") == false)
    }

    /// **A pattern that will not compile matches nothing, and used to match everything.** An
    /// unbalanced `[` is a malformed glob; the guard read `else { return true }`, so a filter
    /// written to NARROW a set admitted every candidate instead, with no diagnostic.
    @Test("a malformed glob matches nothing rather than everything")
    func malformedGlobMatchesNothing() {
        #expect("totally/unrelated.txt".isMatching(searchPattern: "a[b") == false)
    }

    @Test("isMatching is anchored at start and end")
    func isMatchingAnchored() {
        #expect("MyClass".isMatching(searchPattern: "Class") == false)
        #expect("MyClass".isMatching(searchPattern: "My") == false)
    }

    // MARK: - xmlEscaped

    @Test("xmlEscaped escapes the four markup characters")
    func xmlEscapedEscapesMarkup() {
        #expect("a & b <c> \"d\"".xmlEscaped == "a &amp; b &lt;c&gt; &quot;d&quot;")
    }

    /// XML 1.0 forbids every C0 control but TAB, LF and CR, and rejects a character reference to
    /// one too, so each is replaced by its Control Pictures glyph rather than escaped (#80).
    @Test(
        "xmlEscaped replaces a forbidden C0 control with its control picture",
        arguments: (UInt32(0x00)...0x1F).filter { ![0x09, 0x0A, 0x0D].contains($0) }
    )
    func xmlEscapedReplacesForbiddenControl(value: UInt32) throws {
        let control = try #require(Unicode.Scalar(value))
        let picture = try #require(Unicode.Scalar(0x2400 + value))
        let escaped = "a\(Character(control))b".xmlEscaped
        #expect(Array(escaped.unicodeScalars) == ["a", picture, "b"])
    }

    @Test("xmlEscaped keeps tab, line feed and carriage return, which XML allows")
    func xmlEscapedKeepsLegalWhitespace() {
        #expect(Array("a\tb\nc\rd".xmlEscaped.unicodeScalars) == Array("a\tb\nc\rd".unicodeScalars))
    }

    @Test("xmlEscaped replaces U+FFFE and U+FFFF, which XML forbids, with U+FFFD")
    func xmlEscapedReplacesForbiddenNoncharacters() {
        #expect(Array("a\u{FFFE}b\u{FFFF}c".xmlEscaped.unicodeScalars) == ["a", "\u{FFFD}", "b", "\u{FFFD}", "c"])
    }

    @Test("xmlEscaped leaves the legal characters at the edges of the forbidden ranges alone", arguments: [
        "\u{20}", "\u{7F}", "\u{85}", "\u{D7FF}", "\u{E000}", "\u{FFFD}", "\u{10000}", "\u{10FFFF}", "👨‍👩‍👧"
    ])
    func xmlEscapedKeepsLegalCharacters(text: String) {
        #expect(Array(text.xmlEscaped.unicodeScalars) == Array(text.unicodeScalars))
    }

    /// `<` followed by a combining mark is a single `Character` that is not `"<"`, so the old
    /// `Character`-based `replacingOccurrences` chain left the `<` raw (#80).
    @Test("xmlEscaped escapes a markup character that a combining mark follows")
    func xmlEscapedEscapesMarkupBeforeCombiningMark() {
        let escaped = "<\u{301}&\u{301}>\u{301}\"\u{301}".xmlEscaped
        let expected = "&lt;\u{301}&amp;\u{301}&gt;\u{301}&quot;\u{301}"
        #expect(Array(escaped.unicodeScalars) == Array(expected.unicodeScalars))
    }

    /// Every Unicode scalar, in one text node, so no character can make the output malformed.
    @Test("xmlEscaped text holding every Unicode scalar parses as XML")
    func xmlEscapedTextOfEveryScalarIsWellFormed() {
        var scalars = String.UnicodeScalarView()
        for value in UInt32(0)...0x10FFFF {
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        let document = "<text>\(String(scalars).xmlEscaped)</text>"
        #expect(WellFormedXML.error(in: document) == nil)
    }

    // MARK: - addOrSkipMemberAccessLevelAttribute

    @Test(
        "addOrSkipMemberAccessLevelAttribute writes the symbol matching accessibility",
        arguments: [
            (ElementAccessibility.public, "+"),
            (ElementAccessibility.internal, "~"),
            (ElementAccessibility.private, "-")
        ]
    )
    func addAccessLevelSymbol(accessibility: ElementAccessibility, expected: String) {
        var output = ""
        let element = SyntaxStructure(accessibility: accessibility, kind: .varInstance, name: "foo")
        output.addOrSkipMemberAccessLevelAttribute(for: element, basedOn: .default)
        #expect(output == expected)
    }

    @Test("addOrSkipMemberAccessLevelAttribute skips when showMemberAccessLevelAttribute is false")
    func skipWhenDisabled() {
        var output = ""
        let element = SyntaxStructure(accessibility: .public, kind: .functionMethodInstance, name: "foo")
        let config = Configuration(
            elements: ElementOptions(showMemberAccessLevelAttribute: false)
        )
        output.addOrSkipMemberAccessLevelAttribute(for: element, basedOn: config)
        #expect(output == "")
    }
}
