import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// What a name built on the type around the writer means when no file has a module (#252):
// `class W: X` inside `extension Foo` means a member of the `Foo` that extension extends. A member
// an extension adds ranks in the extension's own file (#230), so one that another target's `Foo`
// gets through a typealias of it can rank in, or near, the writer's file, and it must not win for
// that. Each fixture was checked as a package with `swift build`, with the `import` lines added that
// the fixtures leave out, and `--package` says the same as the expected ends.

private typealias Fixture = NearestDirectoryFixture

@Suite("A name built on the type around the writer means a member of that type, without a module")
struct EnclosingTypeMemberRankTests {

    private static let otherTargetsFoo: Fixture.File = (
        "/r/Sources/A/Foo.swift", "public struct Foo { public init() {} }\npublic typealias AF = Foo"
    )

    private func enclosingWriterLines(
        _ files: [Fixture.File], mode: ExtensionVisualization, reversed: Bool
    ) throws -> Set<String> {
        let ordered = reversed ? files.reversed() : files
        let lines = try Fixture.lines(ordered, .plantuml, ElementOptions(showExtensions: mode))
        return Set(lines.filter { $0.contains("<|") })
    }

    private func enclosingWriterEdges(
        _ files: [Fixture.File], mode: ExtensionVisualization, reversed: Bool
    ) throws -> [String] {
        let ordered = reversed ? files.reversed() : files
        return try Fixture.edges(ordered, ElementOptions(showExtensions: mode)).filter { $0.contains("W ->") }
    }

    /// `X` is built on the `extension Foo` around `W`, B's `Foo`, so RB is meant: `AF` is A's `Foo`,
    /// and RE's alias, though in `W`'s own file, is no member of B's (#252).
    @Test("a writer inside an extension does not take an alias in its file added to another same-named type",
          arguments: [ExtensionVisualization.all, .merged, .hidden], [false, true])
    func writerInsideOwnExtension(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [Fixture.File] = [
            Self.otherTargetsFoo,
            ("/r/Sources/B/Foo.swift", "struct Foo { typealias X = RB }\nclass RB {}"),
            ("/r/Sources/B/E.swift", """
            extension AF { typealias X = RE }
            class RE {}
            extension Foo { class W: X {} }
            """)
        ]
        #expect(try enclosingWriterLines(files, mode: mode, reversed: reversed) == ["RB <|-- Foo.W : inherits"])
        #expect(try enclosingWriterEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> RB"])
    }

    /// The same, with the alias only near `W`, in another file of its directory (#252).
    @Test("a writer inside an extension does not take an alias near it added to another same-named type",
          arguments: [ExtensionVisualization.all, .merged, .hidden], [false, true])
    func writerInsideExtensionNearAlias(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [Fixture.File] = [
            Self.otherTargetsFoo,
            ("/r/Sources/B/Foo.swift", "struct Foo { typealias X = RB }\nclass RB {}"),
            ("/r/Sources/B/Sub/E.swift", "extension AF { typealias X = RE }\nclass RE {}"),
            ("/r/Sources/B/Sub/W.swift", "extension Foo { class W: X {} }")
        ]
        #expect(try enclosingWriterLines(files, mode: mode, reversed: reversed) == ["RB <|-- Foo.W : inherits"])
        #expect(try enclosingWriterEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> RB"])
    }

    /// `W` in `struct Foo`'s own body, with `extension AF` earlier in its file: merged into A's
    /// `Foo`, that alias ranks in this file too, and first read, it came first (#252).
    @Test("a writer in a type's body does not take an alias merged into another same-named type",
          arguments: [ExtensionVisualization.all, .merged, .hidden], [false, true])
    func writerInTypesBody(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [Fixture.File] = [
            Self.otherTargetsFoo,
            ("/r/Sources/B/Foo.swift", """
            extension AF { typealias X = RE }
            class RE {}
            struct Foo {
                typealias X = RB
                class W: X {}
            }
            class RB {}
            """)
        ]
        #expect(try enclosingWriterLines(files, mode: mode, reversed: reversed) == ["RB <|-- Foo.W : inherits"])
        #expect(try enclosingWriterEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> RB"])
    }

    /// A name built on the type around the writer takes a `public` member of that type's body before
    /// an extension's in another directory, as a dotted name as written does (`bodyBeforeExtension`).
    @Test("a writer inside an extension takes a public member of the type's body before a sibling's",
          arguments: [ExtensionVisualization.all, .merged, .hidden])
    func enclosingBodyBeforeExtension(mode: ExtensionVisualization) throws {
        let files: [Fixture.File] = [
            ("/r/Sources/Core/Foo.swift", """
            public struct Foo { public typealias X = RCore; public init() {} }
            open class RCore { public init() {} }
            """),
            ("/r/Sources/Features/Login/E.swift", "extension Foo { typealias X = RLogin }\nclass RLogin {}"),
            ("/r/Sources/Features/Profile/W.swift", "extension Foo { class W: X {} }")
        ]
        #expect(try enclosingWriterLines(files, mode: mode, reversed: false) == ["RCore <|-- Foo.W : inherits"])
    }

    // MARK: What is kept is keyed by bytes

    /// The directory ranking compares bytes, so what is kept for a writer must too: as strings the
    /// two spellings of `café` are equal, and the second writer asked took the first's answer.
    /// RLogin's extension is in `W1`'s directory alone, so only `W1` keeps it beside Core's public `X`.
    @Test("composed and decomposed spellings of a writer's directory keep candidates of their own",
          arguments: [false, true])
    func candidatesKeyIsItsBytes(reversed: Bool) throws {
        let writers: [Fixture.File] = [
            ("/r/X/caf\u{E9}/W.swift", "extension Foo { class W1: X {} }"),
            ("/r/X/cafe\u{301}/W.swift", "extension Foo { class W2: X {} }")
        ]
        let files: [Fixture.File] = [
            ("/r/Core/Foo.swift", """
            public struct Foo { public typealias X = RCore; public init() {} }
            open class RCore { public init() {} }
            """),
            ("/r/X/caf\u{E9}/E.swift", "extension Foo { typealias X = RLogin }\nclass RLogin {}")
        ] + (reversed ? writers.reversed() : writers)
        #expect(try enclosingWriterLines(files, mode: .all, reversed: false) == [
            "RLogin <|-- Foo.W1 : inherits", "RCore <|-- Foo.W2 : inherits"
        ])
    }

    /// The same for the type around each writer: each `extension Foo` extends the `Foo` in its own
    /// spelling of `café`, so `W1` means A's `X` and `W2` B's.
    @Test("composed and decomposed spellings of a writer's directory keep the type around it apart",
          arguments: [false, true])
    func ownerKeyIsItsBytes(reversed: Bool) throws {
        let writers: [Fixture.File] = [
            ("/r/X/caf\u{E9}/W.swift", "extension Foo { class W1: X {} }"),
            ("/r/X/cafe\u{301}/W.swift", "extension Foo { class W2: X {} }")
        ]
        let files: [Fixture.File] = [
            ("/r/X/caf\u{E9}/A/Foo.swift", "struct Foo { typealias X = RA }\nclass RA {}"),
            ("/r/X/cafe\u{301}/B/Foo.swift", "struct Foo { typealias X = RB }\nclass RB {}"),
            ("/r/Z/E.swift", "extension Foo { class X {} }")
        ] + (reversed ? writers.reversed() : writers)
        #expect(try enclosingWriterLines(files, mode: .all, reversed: false) == [
            "RA <|-- Foo.W1 : inherits", "RB <|-- Foo.W2 : inherits"
        ])
    }

    // MARK: Cost

    /// A directory's layout, `count` times: in `namespace`, each directory adds `NS.X` and writes
    /// `class W: X` inside `extension NS`, where the alias in its own file is the one meant; in
    /// `issue`, each copies `writerInsideOwnExtension`, where only the rest tell the alias in the
    /// writer's file from its own `Foo`'s, with five writers.
    private static func manyDirectories(_ layout: String, count: Int) -> [Fixture.File] {
        guard layout == "issue" else {
            return [("/r/Sources/Root/NS.swift", "enum NS {}")] + (0..<count).map { index in
                ("/r/Sources/D\(index)/E.swift", """
                extension NS { typealias X = R\(index) }
                class R\(index) {}
                extension NS { class W\(index): X {} }
                """)
            }
        }
        return (0..<count).flatMap { index -> [Fixture.File] in
            let writers = (0..<5).map { "class W\(index)x\($0): X {}" }.joined(separator: "\n")
            return [
                ("/r/D\(index)/A/Foo.swift", "public struct Foo { public init() {} }\npublic typealias AF = Foo"),
                ("/r/D\(index)/B/Foo.swift", "struct Foo { typealias X = RB\(index) }\nclass RB\(index) {}"),
                ("/r/D\(index)/B/E.swift", """
                extension AF { typealias X = RE\(index) }
                class RE\(index) {}
                extension Foo {
                \(writers)
                }
                """)
            ]
        }
    }

    /// Fitted by the whole set, each lookup of such a name scanned every same-named extension's
    /// member and looked the type around the writer up anew, so the cost grew with the square of the
    /// directories. In `namespace`, the alias in the writer's own file, a member of its type, again
    /// answers alone, which took it from 11 s of CPU in a debug build to half a second, as main.
    /// In `issue`, where only the rest decide, the writer's type and a scope's candidates are kept,
    /// which took it from 5 s to 1.2 s, as main, which also grows with the square there; without
    /// just one of them it takes about twice as long, too near a slow runner's time to bound.
    @Test("many writers inside extensions among many same-named members cost about a lookup each",
          arguments: [("namespace", 1000, 2.0), ("issue", 150, 3.0)])
    func manyDirectoriesCostALookupEach(layout: String, count: Int, limit: Double) throws {
        let items = try Fixture.parsed(Self.manyDirectories(layout, count: count))
        let configuration = Configuration(elements: ElementOptions(), format: .plantuml)
        var text = ""
        let seconds = ThreadCPUClock.seconds { text = DiagramScript(items: items, configuration: configuration).text }
        #expect(seconds < limit, "\(seconds)")
        let expected = layout == "issue" ? "RB7 <|-- Foo.W7x0 : inherits" : "R7 <|-- NS.W7 : inherits"
        #expect(text.contains(expected))
    }
}
