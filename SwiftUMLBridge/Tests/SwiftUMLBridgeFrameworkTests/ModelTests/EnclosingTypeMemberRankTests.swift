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
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
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
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
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
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
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
          arguments: [ExtensionVisualization.all, .merged, .none])
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
}
