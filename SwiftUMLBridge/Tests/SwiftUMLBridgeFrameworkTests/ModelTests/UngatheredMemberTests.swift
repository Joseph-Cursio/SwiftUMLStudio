import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A dotted name whose member Swift means is one the lookup does not gather, as one a superclass
/// declares or an extension adds through a typealias, and one the diagram hides: the edge ends on
/// no type the writer cannot reach, and a hidden type named through an alias ends where its own
/// name does. Each case builds with swiftc (`ImportAwareRankTests`).
@Suite("A dotted name whose member is not gathered, or hidden, ends where Swift's would or nowhere")
struct UngatheredMemberTests {
    typealias File = ImportAwareRankTests.File

    /// `Foo.V` is the `V` that ModA's `Bar` inherits from `Base`, beside Aaa's own `Bar.V`.
    private static let inheritedMember = [
        File(module: "ModA", source: """
            open class Base {
                public init() {}
                open class V {
                    public init() {}
                    public func vOnly() {}
                }
            }

            open class Bar: Base {}
            """),
        StartedFallbackTests.barWithV(in: "Aaa", member: "zOnly"), StartedFallbackTests.aliasOfBar,
        File(module: "ModC", source: "import ModA\n\nfinal class C: Foo.V {}\n")
    ]
    /// `inheritedMember` with ModC's own `Bar.V` in another file, which the alias does not name.
    private static let inheritedBesideOwnBar = inheritedMember + [
        File(module: "ModC", source: """
            struct Bar {
                class V {
                    func cOnly() {}
                }
            }
            """)
    ]

    /// `Foo.V` is the `V` ModB adds through `FooAlias`, beside Mod0's, which App never loads.
    private static let memberAddedThroughAlias = [
        File(module: "ModA", source: """
            public struct Foo {
                public init() {}
            }

            public typealias FooAlias = Foo
            """),
        File(module: "ModB", source: """
            import ModA

            extension FooAlias {
                open class V {
                    public init() {}
                    public func vOnly() {}
                }
            }
            """),
        File(module: "Mod0", source: """
            import ModA

            extension ModA.Foo {
                open class V {
                    public init() {}
                    public func cOnly() {}
                }
            }
            """),
        File(module: "App", source: "import ModA\nimport ModB\n\nfinal class C: Foo.V {}\n")
    ]

    /// Where Swift's member is one the lookup cannot gather, inherited (`Foo.V` is `Base.V`
    /// after `typealias Foo = ModA.Bar` and `class Bar: Base`) or added through a typealias
    /// (`extension FooAlias { class V }`), `C` ends on no box, not on a type the writer cannot
    /// reach: another target's `Bar.V` (swiftc: `zOnly` does not resolve), the writer
    /// module's own `Bar.V`, which the alias does not name (`cOnly` does not), nor a `V` that a
    /// target no file of App imports adds to `Foo` (`cOnly` does not). The text formats keep
    /// the name as written, `Foo.V`, as no box has it, though `Bar.V` is a drawn box's.
    @Test("a name whose member is not gathered ends on no type the writer cannot reach", arguments: [false, true])
    func endsOnNothingOutOfReach(reversed: Bool) throws {
        let fixtures = [
            (Self.inheritedMember, "zOnly"), (Self.inheritedBesideOwnBar, "cOnly"),
            (Self.memberAddedThroughAlias, "cOnly")
        ]
        for (given, outOfReach) in fixtures {
            let ordered = reversed ? given.reversed() : given
            let files = ordered.map { (module: Optional($0.module), source: $0.source) }
            for mode in [ExtensionVisualization.all, .merged] {
                let elements = ElementOptions(showExtensions: mode)
                let svg = Configuration(elements: elements, format: .svg)
                let items = try moduleQualifiedItems(files)
                let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: svg)
                #expect(graph.owner(of: outOfReach) != nil, "\(outOfReach), \(mode)")
                #expect(!graph.edgeEnds.contains { $0.hasPrefix("C -> ") }, "\(outOfReach), \(mode)")
                let text = DiagramScript(
                    items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
                ).text
                #expect(ClassDiagramIds.lines(of: text, containing: "<|-- C ") == ["Foo.V <|-- C : inherits"],
                        "\(outOfReach), \(mode)")
            }
        }
    }

    /// With nested types hidden, `Foo.V` after `typealias Foo = ModA.Bar` is `Bar.V`, hidden, so
    /// its edge ends where `Bar.V`'s does: on the drawn `extension Bar.V` that stands in for it
    /// (swiftc: `C().more()` resolves).
    @Test("a hidden type named through an alias of its first component ends on its stand-in")
    func hiddenThroughAliasEndsOnStandIn() throws {
        let files: [(module: String?, source: String)] = [
            ("ModA", """
                public struct Bar {
                    public init() {}
                    open class V {
                        public init() {}
                        public func barOnly() {}
                    }
                }

                extension Bar.V {
                    public func more() {}
                }
                """),
            ("ModC", "import ModA\n\ntypealias Foo = ModA.Bar\n"),
            ("ModC", "import ModA\n\nfinal class C: Foo.V {}\n\nfinal class Impl: Bar.V {}\n")
        ]
        let hidden = ElementOptions(showNestedTypes: false)
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: Configuration(elements: hidden, format: .svg)
        )
        let standIn = try #require(graph.owner(of: "more"))
        #expect(graph.edgeEnds.filter { $0.hasPrefix("C -> ") || $0.hasPrefix("Impl -> ") }
            == ["C -> \(standIn)", "Impl -> \(standIn)"])
        let text = DiagramScript(
            items: try moduleQualifiedItems(files), configuration: Configuration(elements: hidden)
        ).text
        let box = try #require(NameStartFallbackTests.plantUMLBox(listing: "more", in: text))
        #expect(ClassDiagramIds.lines(of: text, containing: "<|-- C ") == ["\(box) <|-- C : inherits"])
    }
}
