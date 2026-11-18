@testable import SwiftUMLBridgeFramework
import Testing

// Read without its package, a dotted name whose first component is another name for a project
// type, `Q.Foo` after `typealias Q = Other`, means the `Foo` of that very `Other`, as with
// `--package` (#283). No start was worked out without a module and imports, so the name was looked
// up as written and ended on an undeclared `Q.Foo` box. Each one-directory fixture builds with
// `swiftc -typecheck`, each writer conforming to the protocol expected here, and each fixture as a
// package of one target per directory gives the same ends with `--package`.

private typealias Fixture = NearestDirectoryFixture

@Suite("A dotted name's first component that aliases a project type starts there, without a module")
struct DirectoryAliasStartTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [File]
        /// The PlantUML supertype lines, in any order.
        let lines: [String]
        /// The class-diagram graph's edges from each writer, a type whose name starts with `W`, in
        /// any order.
        let edges: [String]

        var testDescription: String { name }
    }

    struct File: Sendable {
        let path: String
        let source: String
    }

    private static let protocols = "protocol P1 {}\nprotocol P2 {}\n"

    static let cases: [Case] = [
        Case(name: "the issue's reproduction: an alias in the type around the writer", files: [
            File(path: "/r/Sources/A/X.swift", source: protocols + """
                typealias Foo = P1
                enum Other { typealias Foo = P2 }
                enum E { typealias Q = Other; struct W: Q.Foo {} }
                """),
        ], lines: ["P2 <|.. E.W : conforms to"], edges: ["E.W -> P2"]),
        Case(name: "an alias at file scope", files: [
            File(path: "/r/Sources/A/X.swift", source: protocols + """
                enum Other { typealias Foo = P2 }
                typealias Q = Other
                struct W: Q.Foo {}
                """),
        ], lines: ["P2 <|.. W : conforms to"], edges: ["W -> P2"]),
        Case(name: "a member an extension in another file adds to the aliased type", files: [
            File(path: "/r/Sources/A/Real.swift", source: protocols + "enum Real {}"),
            File(path: "/r/Sources/A/Ext.swift", source: "extension Real { typealias Foo = P2 }"),
            File(path: "/r/Sources/A/W.swift", source: "enum E { typealias Q = Real; struct W: Q.Foo {} }"),
        ], lines: ["P2 <|.. E.W : conforms to"], edges: ["E.W -> P2"]),
        Case(name: "the issue's second example: a member added through an alias of a nested type", files: [
            File(path: "/r/Sources/A/X.swift", source: protocols + """
                enum Real { enum X {} }
                extension Real.X { typealias Foo = P2 }
                typealias A1 = Real
                typealias A2 = A1.X
                struct W: A2.Foo {}
                """),
        ], lines: ["P2 <|.. W : conforms to"], edges: ["W -> P2"]),
        Case(name: "two directories, each aliasing its own type of one name", files: [
            File(path: "/r/Sources/A/X.swift", source: """
                protocol PA {}
                enum Other { typealias Foo = PA }
                typealias Q = Other
                struct WA: Q.Foo {}
                """),
            File(path: "/r/Sources/B/X.swift", source: """
                protocol PB {}
                enum Other { typealias Foo = PB }
                typealias Q = Other
                struct WB: Q.Foo {}
                """),
        ], lines: ["PA <|.. WA : conforms to", "PB <|.. WB : conforms to"], edges: ["WA -> PA", "WB -> PB"]),
        Case(name: "another directory's type named like the alias", files: [
            File(path: "/r/Sources/A/X.swift", source: """
                protocol PA {}
                enum Other { typealias Foo = PA }
                typealias Q = Other
                struct WA: Q.Foo {}
                """),
            File(path: "/r/Sources/B/X.swift", source: """
                protocol PB {}
                enum Q { typealias Foo = PB }
                struct WB: Q.Foo {}
                """),
        ], lines: ["PA <|.. WA : conforms to", "PB <|.. WB : conforms to"], edges: ["WA -> PA", "WB -> PB"]),
        // Another target's `Q.Foo` is no member of the aliased type, so it never counts, even
        // where, beside it, a protocol would rank before the typealias it ties with.
        Case(name: "another target's member under the name as written, ranking first if counted", files: [
            File(path: "/r/Sources/Core/Other.swift", source: """
                public protocol P2 {}
                public enum Other { public typealias Foo = P2 }
                """),
            File(path: "/r/Sources/B/Q.swift", source: "public enum Q { public protocol Foo {} }"),
            File(path: "/r/Sources/A/W.swift", source: """
                import Core
                import B
                typealias Q = Other
                struct W: Q.Foo {}
                """),
        ], lines: ["P2 <|.. W : conforms to"], edges: ["W -> P2"]),
        // The alias names A's `Other`, though the writer's own file declares another, nearer by
        // directory, with a member of the name in its body.
        Case(name: "the writer's own file declares another type of the aliased name", files: [
            File(path: "/r/Sources/A/A.swift", source: """
                public protocol PA {}
                public enum Other { public typealias Foo = PA }
                public typealias Q = Other
                """),
            File(path: "/r/Sources/B/B.swift", source: """
                import A
                protocol PB {}
                enum Other { typealias Foo = PB }
                struct W: Q.Foo {}
                """),
        ], lines: ["PA <|.. W : conforms to"], edges: ["W -> PA"]),
        // Of two equally near types of the aliased name, the one the alias names counts, not the
        // one in the directory that sorts first.
        Case(name: "another type of the aliased name in a directory that sorts first", files: [
            File(path: "/r/Sources/Alpha/A.swift", source: """
                public protocol PA {}
                public enum Other { public typealias Foo = PA }
                """),
            File(path: "/r/Sources/Zeta/Z.swift", source: """
                public protocol PZ {}
                public enum Other { public typealias Foo = PZ }
                public typealias Q = Other
                """),
            File(path: "/r/Sources/Writer/W.swift", source: "import Alpha\nimport Zeta\nstruct W: Q.Foo {}"),
        ], lines: ["PZ <|.. W : conforms to"], edges: ["W -> PZ"]),
        // Two declarations of one type, each under its own `#if`, are both that type, whichever
        // the alias is read to and whichever file holds the member.
        Case(name: "a member of one of a type's two declarations under #if", files: [
            File(path: "/r/Sources/A/1.swift", source: "#if !os(Linux)\nenum Other { typealias Foo = P2 }\n#endif"),
            File(path: "/r/Sources/A/2.swift", source: "protocol P2 {}\n#if os(Linux)\nenum Other {}\n#endif"),
            File(path: "/r/Sources/A/3.swift", source: """
                typealias Q = Other
                struct W: Q.Foo {}
                struct W0: Other.Foo {}
                """),
        ], lines: ["P2 <|.. W : conforms to", "P2 <|.. W0 : conforms to"], edges: ["W -> P2", "W0 -> P2"]),
        Case(name: "control: the aliased type's own name", files: [
            File(path: "/r/Sources/A/X.swift", source: protocols + """
                enum Other { typealias Foo = P2 }
                typealias Q = Other
                struct W: Other.Foo {}
                """),
        ], lines: ["P2 <|.. W : conforms to"], edges: ["W -> P2"]),
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which file is read first, and with extensions shown, merged and hidden.
    @Test("the name means the aliased type's member",
          arguments: cases, [ExtensionVisualization.all, .merged, .hidden])
    func meansTheAliasedMember(_ testCase: Case, mode: ExtensionVisualization) throws {
        for reversed in [false, true] {
            let given = testCase.files.map { (path: $0.path, source: $0.source) }
            let files = reversed ? given.reversed() : given
            let elements = ElementOptions(showExtensions: mode)
            let lines = try Fixture.lines(files, .plantuml, elements).filter { $0.contains("<|") }
            #expect(Set(lines) == Set(testCase.lines), "reversed: \(reversed)")
            #expect(lines.count == testCase.lines.count, "reversed: \(reversed)")
            let edges = try Fixture.edges(files, elements).filter { edge in
                edge.prefix { $0 != " " }.split(separator: ".").last?.hasPrefix("W") == true
            }
            #expect(Set(edges) == Set(testCase.edges), "reversed: \(reversed)")
        }
    }

    /// A `public` member of the type's body comes before an internal one that another directory's
    /// extension adds, as for the name written out (#253): Swift does not let `C` see `Ae`'s. Which
    /// of the two `Foo` boxes gets the plain id goes by read order, so the check is that `W` ends
    /// on the box `W2` does, the one nested in the struct and not in the extension.
    @Test("a public body member comes before another directory's extension member",
          arguments: [ExtensionVisualization.all, .merged, .hidden])
    func bodyMemberBeforeExtensionMember(mode: ExtensionVisualization) throws {
        let given: [Fixture.File] = [
            ("/r/Sources/Zt/Other.swift", "public struct Other { open class Foo { public init() {} } }"),
            ("/r/Sources/Ae/Ext.swift", "import Zt\nextension Other { class Foo {} }"),
            ("/r/Sources/C/Use.swift", """
            import Zt
            import Ae
            typealias Q = Other
            class W: Q.Foo {}
            class W2: Other.Foo {}
            """),
        ]
        for reversed in [false, true] {
            let files = reversed ? given.reversed() : given
            let lines = try Fixture.lines(files, .plantuml, ElementOptions(showExtensions: mode))
            let writerEnd = try #require(Self.supertype(of: "W", in: lines), "reversed: \(reversed)")
            #expect(Self.supertype(of: "W2", in: lines) == writerEnd, "reversed: \(reversed)")
            let structIds = Set(lines.compactMap(Self.structId))
            let nesting = lines.first { $0.hasSuffix(" +-- \(writerEnd)") }
            #expect(nesting.map { structIds.contains(Self.firstWord(of: $0)) } == true, "reversed: \(reversed)")
            let edges = try Fixture.edges(files, ElementOptions(showExtensions: mode))
            let writerEdges = edges.filter { $0.hasPrefix("W -> ") || $0.hasPrefix("W2 -> ") }
            #expect(writerEdges.count == 2, "reversed: \(reversed)")
            #expect(Set(writerEdges.map { $0.drop { $0 != ">" } }).count == 1, "reversed: \(reversed)")
        }
    }

    private static func firstWord(of line: String) -> String {
        String(line.prefix { $0 != " " })
    }

    /// The id `writer`'s supertype edge ends on in PlantUML `lines`.
    private static func supertype(of writer: String, in lines: [String]) -> String? {
        lines.first { $0.hasSuffix(" <|-- \(writer) : inherits") }.map(firstWord)
    }

    /// The id a PlantUML line declares a struct box under, as `class "Other" as Other << (S, … struct >>`.
    private static func structId(_ line: String) -> String? {
        guard line.contains(" struct >>"), let alias = line.range(of: " as ") else { return nil }
        return firstWord(of: String(line[alias.upperBound...]))
    }
}
