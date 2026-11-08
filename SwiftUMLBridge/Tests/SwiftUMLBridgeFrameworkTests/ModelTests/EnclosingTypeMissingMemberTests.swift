import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// What a name written inside a type means when that type has no member of the name, but another
// same-named type does (#252): `class W: X` inside `extension Foo`, where only another module's
// `Foo` has an `X`, means the `X` further out, as Swift finds no `Foo.X` and reads on. Each module
// fixture but `noTypeFurtherOut`, whose `X` stands for one a module outside the diagram declares,
// was built as a package with `swift build` and a line that compiles only for the meant
// superclass, and the CLI with `--package` gives the same ends.

/// Module fixtures read as `--package` reads them, in either order, drawn as PlantUML lines or as
/// the class diagram's edges.
enum ModuleFixture {
    typealias File = (module: String?, source: String)

    static func inheritsLines(
        _ files: [File], mode: ExtensionVisualization = .all, reversed: Bool
    ) throws -> Set<String> {
        let items = try moduleQualifiedItems(reversed ? files.reversed() : files)
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode))
        return Set(DiagramScript(items: items, configuration: configuration).text
            .split(separator: "\n").map(String.init).filter { $0.contains("<|") && $0.contains(".W") })
    }

    static func writerEdges(_ files: [File], mode: ExtensionVisualization, reversed: Bool) throws -> [String] {
        let items = try moduleQualifiedItems(reversed ? files.reversed() : files)
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        return LayoutGraphBuilder.buildClassDiagram(from: items, configuration: configuration).edges
            .map { "\($0.sourceId) -> \($0.targetId)" }.filter { $0.contains("W ->") }
    }
}

@Suite("With modules, a name written inside a type that lacks it means the name further out")
struct EnclosingTypeMissingMemberTests {

    private static let otherModulesFoo: ModuleFixture.File = (
        "A", "public struct Foo { public init() {} }\npublic typealias AF = Foo"
    )

    /// B's `Foo` has no `X`, so `W`, in an extension of it, means B's top-level `X`, not the alias
    /// `extension AF` adds to A's `Foo` in `W`'s own file.
    @Test("a writer inside an extension of a type with no such member takes the top-level type",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func extensionMemberOfAnotherType(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            Self.otherModulesFoo,
            ("B", "import A\nstruct Foo {}\nclass X {}"),
            ("B", """
            import A
            extension AF { typealias X = RE }
            class RE {}
            extension Foo { class W: X {} }
            """)
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed) == ["X <|-- Foo.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> X"])
    }

    /// A member another `Foo`'s own body declares is no more B's `Foo`'s, though it is the only
    /// `Foo.X` there is.
    @Test("a writer inside an extension does not take a member of another same-named type's body",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func bodyMemberOfAnotherType(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", """
            public struct Foo { public typealias X = RA; public init() {} }
            open class RA { public init() {} }
            """),
            ("B", "import A\nstruct Foo {}\nclass X {}"),
            ("B", "import A\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed) == ["X <|-- Foo.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> X"])
    }

    /// `W` in `struct Foo`'s own body, which has no `X`, with `extension AF` earlier in its file.
    @Test("a writer in a type's body with no such member takes the top-level type",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func writerInBodyOfTypeWithoutMember(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            Self.otherModulesFoo,
            ("B", """
            import A
            extension AF { typealias X = RE }
            class RE {}
            struct Foo { class W: X {} }
            class X {}
            """)
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed) == ["X <|-- Foo.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> X"])
    }

    /// `W` nested in `Inner`, in the extension: neither `Foo.Inner` nor `Foo` has an `X`, so each of
    /// the names built on them gives way, the outer one too.
    @Test("a writer nested inside an extension takes the top-level type past each type around it",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func nestedWriter(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            Self.otherModulesFoo,
            ("B", "import A\nstruct Foo {}\nclass X {}"),
            ("B", """
            import A
            extension AF { typealias X = RE }
            class RE {}
            extension Foo { struct Inner { class W: X {} } }
            """)
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed)
            == ["X <|-- Foo.Inner.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed) == ["Foo.Inner.W -> X"])
    }

    /// With no `X` in the diagram but another `Foo`'s, `W`'s is one it does not declare, as an
    /// imported module's would be: no edge to RE.
    @Test("a writer whose type lacks the name and sees no other draws no edge to another type's member",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func noTypeFurtherOut(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            Self.otherModulesFoo,
            ("B", "import A\nstruct Foo {}"),
            ("B", """
            import A
            extension AF { typealias X = RE }
            class RE {}
            extension Foo { class W: X {} }
            """)
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed) == ["X <|-- Foo.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed).isEmpty)
    }

    // MARK: The type's own member still comes first

    /// A member an extension in another module adds to the very `Foo` `W`'s extension extends is
    /// that type's, so it beats the top-level `X` beside `W`.
    @Test("a writer takes a member another module's extension adds to its own type",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func ownTypesExtensionMember(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", "public struct Foo { public init() {} }"),
            ("A", "extension Foo { public typealias X = RA }\nopen class RA { public init() {} }"),
            ("B", "import A\nclass X {}\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed) == ["RA <|-- Foo.W : inherits"])
        #expect(try ModuleFixture.writerEdges(files, mode: mode, reversed: reversed) == ["Foo.W -> RA"])
    }

    /// `extension AF` extends A's `Foo`, through the alias, so `X` is A's member, beside B's own
    /// `Foo` and its top-level `X`.
    @Test("a writer in an extension spelled through a typealias takes the aliased type's member",
          arguments: [ExtensionVisualization.all, .merged, .none], [false, true])
    func memberThroughAlias(mode: ExtensionVisualization, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", """
            public struct Foo { public typealias X = RA; public init() {} }
            open class RA { public init() {} }
            public typealias AF = Foo
            """),
            ("B", "import A\nstruct Foo {}\nclass X {}"),
            ("B", "import A\nextension AF { class W: X {} }")
        ]
        let lines = try ModuleFixture.inheritsLines(files, mode: mode, reversed: reversed)
        #expect(lines.count == 1 && lines.allSatisfy { $0.hasPrefix("RA <|-- ") }, "\(lines)")
    }

    /// `W`'s `Foo` is A's, which has an `X`, so the name stays built on it, and the top-level `X`
    /// beside `W` is not meant. Of the two `Foo.X`, Swift means A's; the nearest, though, is the
    /// alias B's own module adds to C's `Foo`, an older gap the lookup still has.
    @Test("a writer whose type has the member never falls back to the top-level type", arguments: [false, true])
    func ownMemberFarther(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", """
            public struct Foo { public typealias X = RA; public init() {} }
            open class RA { public init() {} }
            """),
            ("C", "public struct Foo { public init() {} }\npublic typealias CF = Foo"),
            ("B", """
            import struct A.Foo
            import typealias C.CF
            extension CF { typealias X = RC }
            class RC {}
            class X {}
            extension Foo { class W: X {} }
            """)
        ]
        let lines = try ModuleFixture.inheritsLines(files, reversed: reversed)
        #expect(lines.count == 1 && !lines.contains("X <|-- Foo.W : inherits"), "\(lines)")
        withKnownIssue("the nearest Foo.X is C's, from B's own module") {
            #expect(lines == ["RA <|-- Foo.W : inherits"])
        }
    }

    // MARK: Without modules

    /// Read without its package, which same-named `Foo` `W`'s extension extends is a guess by
    /// directory that real layouts defeat, so the name stays built on it, and `W` keeps the alias
    /// that `extension AF` adds to A's `Foo`, as before.
    @Test("without modules, a writer's type lacking the name keeps another type's member", arguments: [false, true])
    func withoutModules(reversed: Bool) throws {
        let files: [NearestDirectoryFixture.File] = [
            ("/r/Sources/A/Foo.swift", "public struct Foo { public init() {} }\npublic typealias AF = Foo"),
            ("/r/Sources/B/Foo.swift", "struct Foo {}\nclass X {}"),
            ("/r/Sources/B/E.swift", """
            extension AF { typealias X = RE }
            class RE {}
            extension Foo { class W: X {} }
            """)
        ]
        let lines = try NearestDirectoryFixture.lines(reversed ? files.reversed() : files, .plantuml)
        withKnownIssue("without --package, the type around the writer is not told from another") {
            #expect(lines.contains("X <|-- Foo.W : inherits"))
        }
    }
}
