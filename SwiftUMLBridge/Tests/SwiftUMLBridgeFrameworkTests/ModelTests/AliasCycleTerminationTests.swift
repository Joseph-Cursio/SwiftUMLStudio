@testable import SwiftUMLBridgeFramework
import Testing

/// A step along a chain of typealiases no longer uses up the lookup's depth (#248), so what ends a
/// cycle of them is the chain coming back to an alias it followed (`AliasChain`), and what ends a
/// loop through the lookups made inside a step is still the depth guard. Swift rejects every
/// source here but the #244 one; each must still be drawn, in every format, with or without a
/// module, whichever file is read first.
@Suite("A cycle of typealiases still ends")
struct AliasCycleTerminationTests {
    static let sources: [(name: String, source: String)] = [
        ("two aliases of each other", """
            protocol P {}
            typealias A = B
            typealias B = A
            struct W: A {}
            extension A {}
            extension B {}
            """),
        ("a long tail into a cycle of three", (1...20).map { "typealias T\($0) = T\($0 + 1)" }.joined(separator: "\n")
            + "\ntypealias T21 = C1\ntypealias C1 = C2\ntypealias C2 = C3\ntypealias C3 = C1\nstruct W: T1 {}"),
        ("an alias of its own member", "typealias X = X.Y\nstruct W: X {}"),
        ("an alias of its own member, which an extension declares", """
            typealias X = X.Y
            extension X {
                typealias Y = Int
                class Sub: Base {}
            }
            class Base {}
            """),
        ("an alias of a type nested in an extension of it", """
            typealias X = X.Y
            extension X {
                struct Y {}
                class Z: Y {}
            }
            struct W: X.Y {}
            """),
        ("an extension of a cycle declaring an alias", """
            typealias D = E
            typealias E = D
            extension D {
                typealias S = Int
                class C: S {}
            }
            """),
        ("an alias of its own member, extended", """
            typealias Crate = Crate.Inner
            extension Crate.Inner {
                class C: Base {}
            }
            class Base {}
            """),
        ("an alias of its own member, extended through another alias", """
            typealias Crate = Crate.Inner
            extension Crate { typealias D = Unknown }
            extension Crate.D { func f() {} }
            extension Crate { class C: Missing {} }
            """),
        ("aliases of each other's members", "typealias A = B.X\ntypealias B = A.Y\nstruct W: A {}"),
        ("a type named like the module it is in (#244)", """
            enum M {
                class V { func outer() {} }
                enum M {
                    class V { func inner() {} }
                    class W: M.V {}
                }
            }
            """),
    ]

    @Test("the diagram is drawn", arguments: sources.map(\.name), [false, true])
    func isDrawn(_ name: String, withModule: Bool) throws {
        let source = try #require(Self.sources.first { $0.name == name }).source
        let module: String? = withModule ? "M" : nil
        // In one file, and split over two read in each order, since the order fills the memos.
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let half = lines.count / 2
        let split = [lines[..<half].joined(separator: "\n"), lines[half...].joined(separator: "\n")]
        for files in [[source], split, split.reversed()] {
            let given = files.map { (module: module, source: $0) }
            for format in [DiagramFormat.plantuml, .mermaid, .nomnoml] {
                let configuration = Configuration(format: format)
                let text = DiagramScript(items: try moduleQualifiedItems(given), configuration: configuration).text
                #expect(!text.isEmpty)
            }
            let graph = LayoutGraphBuilder.buildClassDiagram(
                from: try moduleQualifiedItems(given), configuration: Configuration(format: .svg)
            )
            #expect(!graph.nodes.isEmpty)
        }
    }

    /// A writer whose chain is sound takes nothing from one that runs into a cycle, though both
    /// look up names the shared memos keep.
    @Test("a cycle beside a long chain leaves the chain's edge", arguments: [false, true])
    func cycleBesideChain(reversed: Bool) throws {
        let chain = "protocol P1 {}\n" + (1...12).map { "typealias A\($0) = \($0 == 1 ? "P1" : "A\($0 - 1)")" }
            .joined(separator: "\n") + "\nstruct W1: A12 {}"
        let cycle = "typealias C = D\ntypealias D = C\nstruct W2: C {}\nstruct W3: A12 {}"
        let given = [(module: Optional("App"), source: chain), (module: Optional("App"), source: cycle)]
        let items = try moduleQualifiedItems(reversed ? given.reversed() : given)
        let text = DiagramScript(items: items, configuration: Configuration()).text
        let lines = Set(ClassDiagramIds.lines(of: text, containing: "<|"))
        #expect(lines.isSuperset(of: ["P1 <|.. W1 : conforms to", "P1 <|.. W3 : conforms to"]), "\(lines)")
    }
}
