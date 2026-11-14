@testable import SwiftUMLBridgeFramework
import Testing

/// Swift reads a dotted name's first component as a module only when no type of that name is in
/// scope, and the members of the enclosing types come first. So in `enum E { typealias ModA = Other }`,
/// `ModA.Foo` is `Other.Foo`, even in a module named ModA. The lookup asked only for top-level
/// types of the name and read the module, ending the edge on its `Foo` (#246). Each case with
/// modules builds with swiftc, which makes each writer conform to the protocol expected here.
@Suite("A member of an enclosing type named like a module keeps the name a type")
struct EnclosingNameShadowsModuleTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [File]
        /// The PlantUML supertype lines, in any order.
        let expected: [String]

        var testDescription: String { name }
    }

    struct File: Sendable {
        let module: String?
        let source: String
    }

    private static let protocols = File(module: "ModA", source: """
        protocol P1 {}
        protocol P2 {}
        protocol P3 {}
        typealias Foo = P1
        enum Other { typealias Foo = P2 }
        enum Third { typealias Foo = P3 }
        """)

    static let cases: [Case] = [
        Case(name: "the issue's reproduction", files: [
            protocols, File(module: "ModA", source: "enum E { typealias ModA = Other; struct W: ModA.Foo {} }")
        ], expected: ["P2 <|.. E.W : conforms to"]),
        Case(name: "two enclosing types, each with its own alias", files: [
            protocols, File(module: "ModA", source: """
                enum E2 { typealias ModA = Other; struct W: ModA.Foo {} }
                enum E3 { typealias ModA = Third; struct W: ModA.Foo {} }
                """),
        ], expected: ["P2 <|.. E2.W : conforms to", "P3 <|.. E3.W : conforms to"]),
        Case(name: "the alias two enclosing types out", files: [
            protocols,
            File(module: "ModA", source: "enum Deep { typealias ModA = Other; enum Inner { struct W: ModA.Foo {} } }"),
        ], expected: ["P2 <|.. Deep.Inner.W : conforms to"]),
        Case(name: "the writer in an extension of the type with the alias", files: [
            protocols,
            File(module: "ModA", source: "enum Ext { typealias ModA = Other }"),
            File(module: "ModA", source: "extension Ext { struct W: ModA.Foo {} }"),
        ], expected: ["P2 <|.. Ext.W : conforms to"]),
        Case(name: "control: at the top level beside it, the module", files: [
            protocols, File(module: "ModA", source: """
                enum E { typealias ModA = Other; struct W: ModA.Foo {} }
                struct W0: ModA.Foo {}
                """),
        ], expected: ["P2 <|.. E.W : conforms to", "P1 <|.. W0 : conforms to"]),
        Case(name: "control: an enclosing alias of another name", files: [
            protocols, File(module: "ModA", source: "enum E { typealias Q = Other; struct W: Q.Foo {} }")
        ], expected: ["P2 <|.. E.W : conforms to"]),
        Case(name: "a writer importing the module it names", files: [
            File(module: "ModA", source: "public protocol P1 {}\npublic typealias Foo = P1"),
            File(module: "ModB", source: """
                import ModA
                protocol P2 {}
                enum Other { typealias Foo = P2 }
                enum E { typealias ModA = Other; struct W: ModA.Foo {} }
                struct W0: ModA.Foo {}
                """),
        ], expected: ["P2 <|.. E.W : conforms to", "P1 <|.. W0 : conforms to"]),
        // Writers of no module share a lookup by name, module and imports, which these two hold
        // alike, so the enclosing alias must keep each to its own answer. With no start worked out,
        // an enclosing alias is not followed under any name, so `E.W` ends on an undeclared
        // `ModA.Foo`, as `Q.Foo` does there, and not on the module's `Foo`.
        Case(name: "writers of no module, with and without the alias", files: [
            File(module: "ModA", source: "public protocol P1 {}\npublic typealias Foo = P1"),
            File(module: nil, source: "import ModA\nprotocol P2 {}\nenum Other { typealias Foo = P2 }"),
            File(module: nil, source: "import ModA\nenum E { typealias ModA = Other; struct W: ModA.Foo {} }"),
            File(module: nil, source: "import ModA\nstruct W0: ModA.Foo {}"),
        ], expected: ["ModA.Foo <|-- E.W : inherits", "P1 <|.. W0 : conforms to"]),
    ]

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which file is read first.
    @Test("the name means the enclosing type's member", arguments: cases, [false, true])
    func meansTheEnclosingMember(_ testCase: Case, reversed: Bool) throws {
        let given = testCase.files.map { (module: $0.module, source: $0.source) }
        let items = try moduleQualifiedItems(reversed ? given.reversed() : given)
        let text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        let lines = ClassDiagramIds.lines(of: text, containing: "<|")
        #expect(Set(lines) == Set(testCase.expected))
        #expect(lines.count == testCase.expected.count)
    }
}
