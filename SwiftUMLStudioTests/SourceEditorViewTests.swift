import Foundation
import Testing
@testable import SwiftUMLStudio

@Suite("SourceEditorView.lineRange")
struct SourceEditorViewLineRangeTests {

    private static let threeLines = "abc\ndef\nghi"

    @Test("first line range covers the first segment")
    func firstLine() throws {
        let range = try #require(SourceEditorView.lineRange(line: 1, in: Self.threeLines))
        #expect(range == NSRange(location: 0, length: 3))
    }

    @Test("middle line range starts after the first newline")
    func middleLine() throws {
        let range = try #require(SourceEditorView.lineRange(line: 2, in: Self.threeLines))
        #expect(range == NSRange(location: 4, length: 3))
    }

    @Test("last line range starts after the second newline")
    func lastLine() throws {
        let range = try #require(SourceEditorView.lineRange(line: 3, in: Self.threeLines))
        #expect(range == NSRange(location: 8, length: 3))
    }

    @Test("line numbers below 1 return nil")
    func zeroOrNegativeLine() {
        #expect(SourceEditorView.lineRange(line: 0, in: Self.threeLines) == nil)
        #expect(SourceEditorView.lineRange(line: -1, in: Self.threeLines) == nil)
    }

    @Test("line numbers past the last line return nil")
    func tooLargeLine() {
        #expect(SourceEditorView.lineRange(line: 99, in: Self.threeLines) == nil)
    }

    @Test("trailing newline counts as a final empty line of length zero")
    func trailingNewlineEmptyLine() throws {
        let source = "first\nsecond\n"
        let range = try #require(SourceEditorView.lineRange(line: 3, in: source))
        #expect(range == NSRange(location: 13, length: 0))
    }

    @Test("empty source admits a zero-length range for line 1")
    func emptySource() throws {
        let range = try #require(SourceEditorView.lineRange(line: 1, in: ""))
        #expect(range == NSRange(location: 0, length: 0))
    }
}
