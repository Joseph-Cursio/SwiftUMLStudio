import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A chain of `[`, each inside the one before, as in `[[[1]]]` or `[[[Int]]]`, doubled the time
/// SwiftParser and SourceKit take with each `[`: 20 deep took 8 to 15 s a read in a debug build,
/// and 248 deep never finished (#148). Each parser is now given the source with every `[` nested
/// more than `NestedSquareBrackets.limit` deep written as a space, with its `]`.
///
/// Serialized, because the cuts are recorded in the process-wide `SourceReadNotices`, which some
/// of these tests drain, and so the times are not taken while the other cases run.
@Suite("Chains of nested [", .serialized)
struct NestedSquareBracketTests {
    /// A file with `declaration` in `S`, then `let height` and `struct After`, to show the rest of
    /// the file is still read.
    static func file(_ declaration: String) -> String {
        "struct S {\n    \(declaration)\n    let height = 2\n}\nstruct After {}\n"
    }

    static func chain(_ open: String, _ inner: String, _ close: String, depth: Int) -> String {
        String(repeating: open, count: depth) + inner + String(repeating: close, count: depth)
    }

    /// The shapes whose time doubled with each `[`, `depth` deep. The last doubled in SourceKit only.
    static func shapes(depth: Int) -> [(name: String, source: String)] {
        [
            ("literal", "let x = " + chain("[", "1", "]", depth: depth)),
            ("type", "let x: " + chain("[", "Int", "]", depth: depth)),
            ("optional type", "let x: " + chain("[", "Int", "]?", depth: depth)),
            ("dictionary key", "let x: " + chain("[", "Int", ": Int]", depth: depth)),
            ("tuple literal", "let x = " + chain("[(", "1", ")]", depth: depth)),
            ("tuple type", "let x: " + chain("[(Int, ", "Int", ")]", depth: depth)),
            ("generic type", "let x: " + chain("[Array<", "Int", ">]", depth: depth)),
            ("tuple literal after a value", "let x = " + chain("[(1, ", "1", ")]", depth: depth))
        ].map { ($0.0, file($0.1)) }
    }

    /// A class diagram of `source`, and the CPU time the parsing thread spent on it.
    private static func timedClassDiagram(_ source: String) -> (text: String, seconds: Double) {
        let timed = ThreadCPUClock.onParsingThread { classDiagram(source) }
        return (timed.result, timed.seconds)
    }

    private func withSourceFile<Result>(_ source: String, _ body: (URL) throws -> Result) throws -> Result {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nested-brackets-\(UUID().uuidString).swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    private static func classDiagram(_ source: String) -> String {
        ClassDiagramGenerator().generateScript(for: source, with: Configuration(format: .plantuml)).text
    }

    // MARK: - Time

    /// A clock, not `.timeLimit`, because a time limit cannot stop a parse that is running.
    /// The bounds are for a debug build. Unbounded, a 20-deep chain took 8 to 15 s.
    ///
    /// The parsing thread's CPU clock, so time spent waiting for a core does not count (#237): the
    /// tuple type, parsed in 0.4 s on its own, took 2.4 s by the wall clock on a 3-core CI runner.
    @Test("SwiftParser reads a 20-deep chain in under two seconds", arguments: shapes(depth: 20))
    func swiftParser(shape: String, source: String) {
        let time = ThreadCPUClock.onParsingThread { ParsingStack.parse(source).statements.count }.seconds
        #expect(time < 2, "\(shape): \(time) s")
    }

    /// Correct code took 6.5 s by the wall clock on a busy 8-core machine (#237), and with the
    /// cut turned off, as long as 5.6 s on a quiet one, so no wall-clock bound told them apart.
    @Test("a class diagram of a 20-deep chain takes under two seconds on the parsing thread",
          arguments: shapes(depth: 20))
    func classDiagramTime(shape: String, source: String) {
        let time = Self.timedClassDiagram(source).seconds
        #expect(time < 2, "\(shape): \(time) s")
    }

    /// SourceKit reads the source on threads of its own, which the parsing thread's clock does
    /// not see, and this shape doubled in SourceKit alone: 20 deep with the cut turned off, it
    /// took 0.0026 s on the parsing thread and 0.45 s by the wall clock. At 26 deep, uncut, it
    /// took 27 to 48 s by the wall clock, and 0.05 to 0.08 s cut. So the wall clock, with a bound
    /// a busy machine stays far inside, and checked off CI only (`WallClockLimit`).
    @Test("SourceKit reads a 26-deep tuple literal after a value in under ten seconds")
    func sourceKitTime() {
        let source = Self.file("let x = " + Self.chain("[(1, ", "1", ")]", depth: 26))
        let elapsed = ContinuousClock().measure { _ = Self.classDiagram(source) }
        WallClockLimit.expect(elapsed, under: .seconds(10), "\(elapsed)")
    }

    /// 100 deep, as a shape with a `(` or `<` at each level is then 200 levels, inside
    /// `ParsingStack.maximumNestingLevel`; past it, SwiftParser reads the rest of a file as
    /// unexpected text (#145).
    @Test("a 100-deep chain is read, and the rest of the file with it", arguments: shapes(depth: 100))
    func deepChain(shape: String, source: String) {
        let (text, time) = Self.timedClassDiagram(source)
        #expect(time < 8, "\(shape): \(time) s")
        #expect(text.contains("as After "), "\(shape)")
        #expect(text.contains("~height"), "\(shape)")
    }

    @Test("the issue's 248-deep literal and type are read", arguments: [
        file("let x = " + chain("[", "1", "]", depth: 248)), file("let x: " + chain("[", "Int", "]", depth: 248))
    ])
    func issueWitness(source: String) {
        let (text, time) = Self.timedClassDiagram(source)
        #expect(time < 2, "\(time) s")
        #expect(text.contains("as After ") && text.contains("~height"))
    }

    @Test("the declarations around a chain are drawn")
    func declarationsAroundTheChain() {
        let text = Self.classDiagram("""
            struct Before {
                let width = 1
            }

            struct Grid {
                let cells = \(Self.chain("[", "1", "]", depth: 24))
                let height = 2
            }

            struct After {
                let depth = 3
            }
            """)
        for expected in ["as Before ", "~width", "as Grid ", "~cells", "~height", "as After ", "~depth"] {
            #expect(text.contains(expected), "\(expected)")
        }
    }

    // MARK: - What the parsers are given

    @Test("a chain no deeper than the limit is unchanged")
    func atTheLimit() {
        let source = Self.file("let x = " + Self.chain("[", "1", "]", depth: NestedSquareBrackets.limit))
        #expect(NestedSquareBrackets.readable(source) == source)
    }

    @Test("each [ past the limit, and its ], is a space; every other byte is kept")
    func pastTheLimit() {
        let limit = NestedSquareBrackets.limit
        let source = "let é = " + Self.chain("[", "1, [2]", "]", depth: limit) + "\nlet z = 0\n"
        let readable = NestedSquareBrackets.readable(source)
        let expected = "let é = " + Self.chain("[", "1,  2 ", "]", depth: limit) + "\nlet z = 0\n"
        #expect(readable == expected)
        #expect(readable.utf8.count == source.utf8.count)
    }

    /// Twenty `[`, written where they are not code.
    static let notCodePrefixes: [String] = {
        let brackets = String(repeating: "[", count: 20)
        var prefixes: [String] = []
        prefixes.append("// \(brackets)")
        prefixes.append("/* /* \(brackets) */ still a comment */")
        prefixes.append("let s = \"\(brackets)\\\" \(brackets)\"")
        prefixes.append("let s = \"\"\"\n\(brackets)\n\"\"\"")
        prefixes.append("let s = #\"\(brackets)\"\" \\(x) \"#")
        prefixes.append("let r = #/\(brackets)/#")
        return prefixes
    }()

    @Test("brackets in comments, strings and regex literals do not count", arguments: notCodePrefixes)
    func notCode(prefix: String) {
        let source = prefix + "\nlet y = [[[1]]]\n"
        #expect(NestedSquareBrackets.readable(source) == source)
    }

    @Test("brackets in an interpolation count")
    func interpolation() {
        let deep = Self.chain("[", "1", "]", depth: NestedSquareBrackets.limit + 1)
        let source = "let s = \"a \\(" + deep + ") b\"\n"
        #expect(NestedSquareBrackets.readable(source) != source)
    }

    @Test("a [ left open counts only until the brace around it closes")
    func strayBracket() {
        let stray = String(repeating: "[", count: NestedSquareBrackets.limit)
        let source = "func f() { _ = \(stray) }\nlet y = [[1]]\n"
        #expect(NestedSquareBrackets.readable(source) == source)
    }

    // MARK: - Notices

    @Test("a cut is recorded once a file, naming the file and the first [ past the limit")
    func notice() throws {
        _ = SourceReadNotices.drain()
        let source = Self.file("let x = " + Self.chain("[", "1", "]", depth: 24))
        try withSourceFile(source) { url in
            _ = ClassDiagramGenerator().generateScript(for: [url.path], with: Configuration(format: .plantuml))
            _ = StateMachineGenerator().findCandidates(for: [url.path])
            let notices = SourceReadNotices.drain()
            #expect(notices.count == 1)
            let column = "    let x = ".utf8.count + NestedSquareBrackets.limit + 1
            #expect(notices.first?.hasPrefix("\(url.path):2:\(column): a `[` nested more than 10 deep") == true)
        }
        #expect(SourceReadNotices.drain().isEmpty)
    }

    @Test("a file with no chain past the limit records nothing")
    func noNotice() throws {
        _ = SourceReadNotices.drain()
        try withSourceFile(Self.file("let x = [[[1]]]")) { url in
            _ = ClassDiagramGenerator().generateScript(for: [url.path], with: Configuration(format: .plantuml))
        }
        #expect(SourceReadNotices.drain().isEmpty)
    }

    @Test("every generator names the file it cut")
    func everyGenerator() throws {
        let source = Self.file("let x = " + Self.chain("[", "1", "]", depth: 24))
        try withSourceFile(source) { url in
            let paths = [url.path]
            let generators: [(String, () -> Void)] = [
                ("sequence", {
                    _ = SequenceDiagramGenerator().generateScript(
                        for: paths, entryType: "S", entryMethod: "x", with: .default)
                }),
                ("activity", {
                    _ = ActivityDiagramGenerator().generateScript(
                        for: paths, entryType: "S", entryMethod: "x", with: .default)
                }),
                ("state", { _ = StateMachineGenerator().findCandidates(for: paths) }),
                ("er", { _ = ERDiagramGenerator().generateScript(for: paths) }),
                ("deps modules", { _ = DependencyGraphGenerator().generateScript(for: paths, mode: .modules) }),
                ("deps types", { _ = DependencyGraphGenerator().generateScript(for: paths, mode: .types) })
            ]
            for (name, generate) in generators {
                _ = SourceReadNotices.drain()
                generate()
                let notices = SourceReadNotices.drain()
                #expect(notices.count == 1 && notices.first?.hasPrefix(url.path + ":2:") == true, "\(name)")
            }
        }
    }
}
