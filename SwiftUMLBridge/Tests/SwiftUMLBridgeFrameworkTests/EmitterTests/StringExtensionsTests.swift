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
