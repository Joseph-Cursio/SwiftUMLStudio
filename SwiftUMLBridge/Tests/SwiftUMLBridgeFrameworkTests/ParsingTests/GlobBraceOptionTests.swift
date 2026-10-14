import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A `{…}` group in an include or exclude entry expands the entry into one entry per option, so
/// a brace entry means exactly the list of its expansions (#58). Groups used to become a regex
/// alternation whose options got only a stale escape class and skipped the glob translation:
/// `^` and `$` stayed anchors, `*` and `?` regex quantifiers, and an option starting with `*` or
/// `?`, or holding `**`, made the regex invalid, so the whole entry matched nothing.
@Suite("Glob — brace expansion")
struct GlobBraceOptionTests {

    /// Files under a fresh temporary directory, named relative to it.
    private struct Fixture {
        static let files = [
            "a^b.swift", "a$b.swift", "c.swift",
            "Foo.swift", "FooKit.swift", "FooTests.swift", "Foo.swift.orig", "Foo.a.swift", "FooXa.swift",
            "Bar.swift", "BarKit.swift",
            "Mock.swift", "MockNetwork.swift", "Stub.swift",
            "Sub/Foo.swift", "Sub/BarKit.swift", "Sub/Deep/Foo.swift",
            "Src/C.swift", "Src/A/B.swift"
        ]

        let root: URL

        init(files: [String] = Self.files) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlobBraceOptionTests-\(UUID().uuidString)")
            for file in files {
                let url = root.appendingPathComponent(file)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("struct Z {}\n".utf8).write(to: url)
            }
        }

        /// `urls` relative to the root, in the form enumeration reports them, sorted.
        func relative(_ urls: [URL]) -> [String] {
            let prefix = canonicalPath(root.path) + "/"
            return urls.map { String(enumeratedPath(of: $0).dropFirst(prefix.count)) }.sorted()
        }

        /// The files `pattern` selects.
        func selected(by pattern: String) -> [String] {
            relative(matchGlobs(expandGlobs(pattern, in: root.path), in: root.path))
        }

        /// The files `FileCollector` keeps under `options`.
        func collected(honoring options: FileOptions) -> [String] {
            relative(FileCollector().getFiles(for: ["."], in: root.path, honoring: options))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    struct BraceCase: Sendable, CustomTestStringConvertible {
        let pattern: String
        let expected: [String]
        var testDescription: String { pattern }
    }

    static let braceCases = [
        // `^` and `$` are literal characters in a glob, inside braces as outside.
        BraceCase(pattern: "{a^b,c}.swift", expected: ["a^b.swift", "c.swift"]),
        BraceCase(pattern: "{a$b,c}.swift", expected: ["a$b.swift", "c.swift"]),
        // So is `.`: `Foo.a` does not select `FooXa`.
        BraceCase(pattern: "{Foo.a,Bar}.swift", expected: ["Bar.swift", "Foo.a.swift"]),
        // A trailing `*` or `?` is a wildcard, not a quantifier on the character before it.
        BraceCase(pattern: "{Foo*,Bar}.swift", expected: [
            "Bar.swift", "Foo.a.swift", "Foo.swift", "FooKit.swift", "FooTests.swift", "FooXa.swift"
        ]),
        BraceCase(pattern: "{Ba?,FooKit}.swift", expected: ["Bar.swift", "FooKit.swift"]),
        BraceCase(pattern: "**/{Mock*,Stub*}.swift", expected: ["Mock.swift", "MockNetwork.swift", "Stub.swift"]),
        // An option starting with `*` or `?`, or holding `**`, made the regex invalid.
        // `*` stops at `/`: `Sub/BarKit.swift` is not selected.
        BraceCase(pattern: "{*Kit,Bar}.swift", expected: ["Bar.swift", "BarKit.swift", "FooKit.swift"]),
        BraceCase(pattern: "{?ar,Stub}.swift", expected: ["Bar.swift", "Stub.swift"]),
        BraceCase(pattern: "{**/Foo,Bar}.swift", expected: [
            "Bar.swift", "Foo.swift", "Sub/Deep/Foo.swift", "Sub/Foo.swift"
        ]),
        // A `**` ending an option takes the `/` after the group, so it matches no directory too.
        BraceCase(pattern: "{Src/**,Sub}/*.swift", expected: [
            "Src/A/B.swift", "Src/C.swift", "Sub/BarKit.swift", "Sub/Foo.swift"
        ]),
        // Several groups give every combination; a group can nest in an option.
        BraceCase(pattern: "{Foo,Bar}{Kit,Tests}.swift", expected: ["BarKit.swift", "FooKit.swift", "FooTests.swift"]),
        BraceCase(pattern: "{Mock{,Network},Stub}.swift", expected: ["Mock.swift", "MockNetwork.swift", "Stub.swift"]),
        // Spaces around an option are dropped, wherever the group sits in the entry.
        BraceCase(pattern: "Sub/{Foo, BarKit }.swift", expected: ["Sub/BarKit.swift", "Sub/Foo.swift"]),
        // Controls. A plain option is a plain entry, as `Foo.swift` alone is: that file and
        // anything inside it, so not `Foo.swift.orig`.
        BraceCase(pattern: "Foo*.swift", expected: [
            "Foo.a.swift", "Foo.swift", "FooKit.swift", "FooTests.swift", "FooXa.swift"
        ]),
        BraceCase(pattern: "{Foo,Bar}.swift", expected: ["Bar.swift", "Foo.swift"])
    ]

    @Test("a brace option selects what the same glob selects outside braces", arguments: braceCases)
    func braceOptionIsAGlob(braceCase: BraceCase) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.selected(by: braceCase.pattern) == braceCase.expected)
    }

    /// `{L,R}rest` selects exactly what `Lrest` and `Rrest` select between them.
    @Test("brace expansion distributes over its options", arguments: [
        ("Foo*", "Bar*", ".swift"),
        ("*Kit", "Mo?k", ".swift"),
        ("**/Foo", "Ba?", ".swift"),
        ("a^b*", "a$b*", ".swift"),
        ("Mock*", "*Tests", ".swift"),
        ("Src/**", "Sub", "/*.swift"),
        ("**", "Sub", "/Foo.swift"),
        ("Foo", "Bar", ".swift")
    ])
    func braceExpansionDistributes(left: String, right: String, rest: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let braced = fixture.selected(by: "{\(left),\(right)}\(rest)")
        let separately = Set(fixture.selected(by: left + rest)).union(fixture.selected(by: right + rest))
        #expect(!separately.isEmpty)
        #expect(braced == separately.sorted())
    }

    /// A group makes the list a glob list even when its options hold no glob syntax, as it did
    /// before groups expanded, so `Fo` beside it still names exactly `Fo`, and none of the files
    /// whose names merely begin with it.
    @Test("a brace-free entry means the same beside a group of plain options")
    func braceFreeEntryBesidePlainGroup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.selected(by: "Fo,{Mock,Stub}.swift") == ["Mock.swift", "Stub.swift"])
    }

    // MARK: - Directories an Option Names

    @Test("an option naming a symlinked directory selects what the symlink alone selects")
    func optionThroughSymlink() throws {
        let fixture = try Fixture(files: ["Real/Foo.swift", "Real/Bar.swift"])
        defer { fixture.remove() }
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("Link"),
            withDestinationURL: fixture.root.appendingPathComponent("Real")
        )
        #expect(fixture.selected(by: "Link/*.swift") == ["Real/Bar.swift", "Real/Foo.swift"])
        #expect(fixture.selected(by: "{Link,Nope}/*.swift") == ["Real/Bar.swift", "Real/Foo.swift"])
    }

    @Test("an option holding an absolute path is anchored there, not under the search directory")
    func absoluteOption() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let absolute = fixture.root.appendingPathComponent("Sub").path
        #expect(fixture.selected(by: "{\(absolute),Nope}/*.swift") == ["Sub/BarKit.swift", "Sub/Foo.swift"])
    }

    // MARK: - Through FileCollector

    @Test("an exclude entry with brace options drops every file either option matches")
    func excludeWithBraceOptions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/{Mock*,*Kit}.swift"]
        #expect(fixture.collected(honoring: options) == [
            "Bar.swift", "Foo.a.swift", "Foo.swift", "FooTests.swift", "FooXa.swift",
            "Src/A/B.swift", "Src/C.swift", "Stub.swift", "Sub/Deep/Foo.swift", "Sub/Foo.swift",
            "a$b.swift", "a^b.swift", "c.swift"
        ])
    }

    /// `FileCollector` joins all its exclude entries into one list, so groups are counted across
    /// entries: here the last entry's group is the eleventh.
    @Test("a brace entry after ten others still expands")
    func manyBraceEntries() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = (0..<10).map { "{Nope\($0),Nada\($0)}.swift" } + ["{Mock*,*Kit}.swift"]
        let kept = fixture.collected(honoring: options)
        #expect(kept.allSatisfy { !["Mock.swift", "MockNetwork.swift", "FooKit.swift", "BarKit.swift"].contains($0) })
        #expect(kept.contains("Sub/BarKit.swift"))
    }

    @Test("an include entry with brace options keeps every file either option matches")
    func includeWithBraceOptions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["{*Kit,Stub}.swift"]
        #expect(fixture.collected(honoring: options) == ["BarKit.swift", "FooKit.swift", "Stub.swift"])
        options.include = ["{Src/**,Bar.swift}"]
        #expect(fixture.collected(honoring: options) == ["Bar.swift", "Src/A/B.swift", "Src/C.swift"])
    }

    // MARK: - expandingBraces

    @Test("expandingBraces expands each entry into one entry per option", arguments: [
        ("Sources/{App,Core}/*.swift", "Sources/App/*.swift,Sources/Core/*.swift"),
        ("{a,b}{c,d}", "ac,ad,bc,bd"),
        ("{a,b{c,d}}.swift", "a.swift,bc.swift,bd.swift"),
        ("x,{a,b}.swift,y", "x,a.swift,b.swift,y"),
        ("{a,}.swift", "a.swift,.swift"),
        ("{a}", "a"),
        ("a{b,c", "a{b,c"),
        ("a}b", "a}b"),
        ("{}", "{}"),
        ("Sources/**/*.swift", "Sources/**/*.swift"),
        ("{Mock, Stub}.swift", "Mock.swift,Stub.swift"),
        ("Mocks/{Mock , Stub }.swift", "Mocks/Mock.swift,Mocks/Stub.swift"),
        // Text that looks like the marks an earlier version used is literal, and ends.
        ("{<<<0>>>,y}.swift", "<<<0>>>.swift,y.swift"),
        ("<<<9>>>{a,b}.swift", "<<<9>>>a.swift,<<<9>>>b.swift"),
        ("Sources/<<<0>>>.swift,{Foo,Bar}.swift", "Sources/<<<0>>>.swift,Foo.swift,Bar.swift"),
        // No path holds a NUL; a list with one is left alone.
        ("a\u{0}{b,c}", "a\u{0}{b,c}")
    ])
    func expandingBracesExpands(paths: String, expected: String) {
        #expect(expandingBraces(in: paths) == expected)
    }

    @Test("expandingBraces expands every group in a long list")
    func expandingBracesLongList() {
        let paths = (0..<11).map { "D\($0)/{A,B}.swift" }.joined(separator: ",")
        let expected = (0..<11).map { "D\($0)/A.swift,D\($0)/B.swift" }.joined(separator: ",")
        #expect(expandingBraces(in: paths) == expected)
    }
}
