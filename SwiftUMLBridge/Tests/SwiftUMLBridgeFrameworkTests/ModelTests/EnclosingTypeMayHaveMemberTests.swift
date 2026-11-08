import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

// When a name written inside a type falls back past that type for want of a member (#252), and
// when it must not, with modules known. A member the type inherits is its own, even from a
// superclass named like it, and one only a module downstream of the writer's adds is none it sees.
// Each fixture was built as a package with `swift build` and a line that compiles only for the
// meant superclass, and the CLI with `--package` gives the same ends.

@Suite("With modules, a name written inside a type keeps a member the type has")
struct EnclosingTypeMayHaveMemberTests {

    private static let core = """
    open class Foo { public init() {}
      open class X { public init() {} }
    }
    public typealias CF = Foo
    """

    // MARK: Inherited members

    /// App's `class Foo` inherits Core's `Foo.X`, recorded under the very name `Foo.X` it is
    /// looked for under, so it is App's `Foo`'s member, not another `Foo`'s.
    @Test("a member inherited from a superclass named like the type is the type's own",
          arguments: ["CF", "Core.Foo"], [false, true])
    func sameNamedSuperclass(superclass: String, reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("Core", Self.core),
            ("App", "import Core\nclass Foo: \(superclass) {}\nclass X {}\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["Foo.X <|-- Foo.W : inherits"])
    }

    /// `W`'s `Foo` is Z's, which inherits nothing; D's same-named `class Foo` inherits an `X`, and
    /// a file of B, which does not depend on D, does not see it.
    @Test("a member inherited by another same-named class is not the type's", arguments: [false, true])
    func inheritedByOtherClass(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("D", """
            open class DBase { public typealias X = RD; public init() {} }
            open class Foo: DBase {}
            open class RD { public init() {} }
            """),
            ("Z", "public struct Foo { public init() {} }"),
            ("B", "import Z\nclass X {}\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["X <|-- Foo.W : inherits"])
    }

    /// App's `Foo` inherits from Ext's, which the diagram does not read: Other's `Foo.X`, though
    /// Ext's `Foo` is named like Other's, is no member it inherits.
    @Test("a superclass outside the diagram brings no other module's member", arguments: [false, true])
    func superclassOutsideDiagram(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("Other", """
            public struct Foo { public typealias X = RO; public init() {} }
            open class RO { public init() {} }
            """),
            ("App", "import Other\nimport Ext\nclass Foo: Ext.Foo {}\nclass X {}\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["X <|-- Foo.W : inherits"])
    }

    /// `Inner.Leaf` in `Sub`, which inherits `Inner` from `Base`, is `Base.Inner.Leaf`: inherited
    /// through `Inner`, which is itself inherited through `Sub`, the writer's own type, and not the
    /// top-level `Inner.Leaf` beside it, a struct no class could inherit from.
    @Test("a member of an inherited nested type is the type's own", arguments: [false, true])
    func memberOfInheritedNestedType(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("Core", "open class Base { public init() {}\n    open class Inner { open class Leaf {} }\n}"),
            ("App", """
            import Core
            enum Inner { struct Leaf {} }
            class Sub: Base {}
            extension Sub { class W1: Inner.Leaf {} }
            extension Sub { struct Nest { class W2: Inner.Leaf {} } }
            class Sub2: Base { class W3: Inner.Leaf {} }
            """)
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == [
            "Base.Inner.Leaf <|-- Sub.W1 : inherits", "Base.Inner.Leaf <|-- Sub.Nest.W2 : inherits",
            "Base.Inner.Leaf <|-- Sub2.W3 : inherits"
        ])
    }

    // MARK: A type around the writer the lookup reads otherwise than Swift

    /// Umbrella's own `Foo` shadows Core's, which its `@_exported import Core` shows App too, so
    /// App's `extension Foo` extends Umbrella's, whose `X` is RU. The lookup takes Core's `Foo` for
    /// it, an older gap, so where Swift's rules do not settle which `Foo` it is, a member of one the
    /// file sees is kept.
    @Test("a member of a type the writer's file sees is kept where the type around it is not settled",
          arguments: [false, true])
    func reexportShadowedType(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("Core", "public struct Foo { public init() {} }"),
            ("Umbrella", """
            @_exported import Core
            public struct Foo { public typealias X = RU; public init() {} }
            open class RU { public init() {} }
            """),
            ("App", "import Umbrella\nclass X { init() {} }\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["RU <|-- Foo.W : inherits"])
    }

    /// A's `Foo` is the writer's, as its file imports it alone (`import struct A.Foo`), though it
    /// also sees D's, so D's `Foo.X` is not its own: Swift means B's top-level `X`.
    @Test("a scoped import settles the type around the writer", arguments: [false, true])
    func scopedImportSettlesType(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", "public struct Foo { public init() {} }"),
            ("D", """
            public struct Foo { public typealias X = RD; public init() {} }
            open class RD { public init() {} }
            """),
            ("B", "import struct A.Foo\nimport D\nclass X {}\nextension Foo { class W: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["X <|-- Foo.W : inherits"])
    }

    // MARK: A module downstream of the writer's

    /// C's extension adds `X` to B's `Foo`, but C depends on B, so B does not load it: B's `Foo`
    /// has no `X` that `W` sees.
    @Test("a member only a downstream module adds is not the type's", arguments: [false, true])
    func downstreamMember(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("D", """
            public struct Foo { public typealias X = RD; public init() {} }
            open class RD { public init() {} }
            """),
            ("B", "public struct Foo { public init() {} }\nclass X {}"),
            ("B", "import D\nextension Foo { class W: X {} }"),
            ("C", "import B\nextension Foo { public typealias X = RC }\nopen class RC { public init() {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["X <|-- Foo.W : inherits"])
    }

    /// The same for a `Foo` B imports, so the type around `W` is not settled: C, downstream of B,
    /// adds the `X` to A's `Foo`, which B sees but does not load.
    @Test("a member only a downstream module adds to an imported type is not the type's", arguments: [false, true])
    func downstreamMemberOfImportedType(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", "public struct Foo { public init() {} }"),
            ("B", "import A\nclass X {}\nextension Foo { class W: X {} }"),
            ("C", "import A\nimport B\nextension Foo { public typealias X = RC }\nopen class RC { public init() {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == ["X <|-- Foo.W : inherits"])
    }

    // MARK: Each writer's own answer

    /// A's `Foo` has an `X` and B's does not: each writer takes its own, though both write
    /// `Foo.X` inside `extension Foo`, and what is kept for one is not the other's.
    @Test("two writers whose types differ in having the member each get their own", arguments: [false, true])
    func writersApart(reversed: Bool) throws {
        let files: [ModuleFixture.File] = [
            ("A", """
            public struct Foo { public typealias X = RA; public init() {} }
            open class RA { public init() {} }
            extension Foo { class W1: X {} }
            """),
            ("B", "struct Foo {}\nclass X {}\nextension Foo { class W2: X {} }")
        ]
        #expect(try ModuleFixture.inheritsLines(files, reversed: reversed) == [
            "RA <|-- Foo.W1 : inherits", "X <|-- Foo.W2 : inherits"
        ])
    }

    // MARK: Cost

    /// A hundred modules, each with twenty writers inside its own `extension Foo`, whose `Foo`
    /// lacks `X`, among a hundred other modules' `Foo`s that get one: each writer's `Foo.X` is
    /// turned down after a scan of every `Foo.X`, once per file, as all of a file's writers find
    /// the same one (`EnclosingLookups`). About 1.8 s of CPU in a debug build, and 2.9 s scanning
    /// for each writer, too near to bound apart; the bound keeps the scan from growing past that.
    @Test("many writers whose type lacks the name cost about a lookup each")
    func manyWritersLackingMember() throws {
        var files: [ModuleFixture.File] = []
        for index in 0..<100 {
            files.append(("T\(index)", """
            public struct Foo { public init() {} }
            extension Foo { public struct X {} }
            public class X {}
            """))
            let writers = (0..<20).map { "class W\(index)x\($0): X {}" }.joined(separator: "\n")
            files.append(("W\(index)", "import T\(index)\nstruct Foo {}\nextension Foo {\n\(writers)\n}"))
        }
        let items = try moduleQualifiedItems(files)
        let configuration = Configuration(elements: ElementOptions(), format: .plantuml)
        var text = ""
        let seconds = ThreadCPUClock.seconds { text = DiagramScript(items: items, configuration: configuration).text }
        #expect(seconds < 6.0, "\(seconds)")
        let edge = text.split(separator: "\n").first { $0.hasSuffix("<|-- Foo.W7x3 : inherits") }
        #expect(edge?.hasPrefix("X") == true, "\(String(describing: edge))")
    }
}
