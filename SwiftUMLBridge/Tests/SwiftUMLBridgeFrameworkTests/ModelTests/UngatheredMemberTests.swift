import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A dotted name whose member Swift means is one the lookup does not gather, as one an extension
/// adds through a typealias, or one a superclass declares, which it now does (#250), and one the
/// diagram hides: the edge ends on Swift's member or on no type the writer cannot reach, and a
/// hidden type named through an alias ends where its own name does. Each case builds with swiftc
/// (`ImportAwareRankTests`).
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

    /// Where Swift's member is one the lookup cannot gather, added through a typealias
    /// (`extension FooAlias { class V }`), `C` ends on no box, not on a type the writer cannot
    /// reach: a `V` that a target no file of App imports adds to `Foo` (`cOnly` does not
    /// resolve). The text formats keep the name as written, `Foo.V`, as no box has it.
    @Test("a name whose member is not gathered ends on no type the writer cannot reach", arguments: [false, true])
    func endsOnNothingOutOfReach(reversed: Bool) throws {
        let ordered = reversed ? Self.memberAddedThroughAlias.reversed() : Self.memberAddedThroughAlias
        let files = ordered.map { (module: Optional($0.module), source: $0.source) }
        for mode in [ExtensionVisualization.all, .merged] {
            let elements = ElementOptions(showExtensions: mode)
            let svg = Configuration(elements: elements, format: .svg)
            let graph = LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: svg)
            #expect(graph.owner(of: "cOnly") != nil, "\(mode)")
            #expect(!graph.edgeEnds.contains { $0.hasPrefix("C -> ") }, "\(mode)")
            let text = DiagramScript(
                items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
            ).text
            #expect(ClassDiagramIds.lines(of: text, containing: "<|-- C ") == ["Foo.V <|-- C : inherits"], "\(mode)")
        }
    }

    /// `Foo.V` after `typealias Foo = ModA.Bar` and `class Bar: Base` is the `V` that `Bar` inherits
    /// from `Base` (swiftc: `vOnly` resolves), so `C` ends on `Base.V`, not on another target's
    /// `Bar.V` (`zOnly` does not resolve) nor the writer module's own `Bar.V`, which the alias does
    /// not name (`cOnly` does not), in SVG and in the text formats (#250).
    @Test("a name whose member a superclass declares ends on that member", arguments: [false, true])
    func inheritedEndsOnSuperclassMember(reversed: Bool) throws {
        for given in [Self.inheritedMember, Self.inheritedBesideOwnBar] {
            let ordered = reversed ? given.reversed() : given
            let files = ordered.map { (module: Optional($0.module), source: $0.source) }
            for mode in [ExtensionVisualization.all, .merged] {
                let elements = ElementOptions(showExtensions: mode)
                let svg = Configuration(elements: elements, format: .svg)
                let items = try moduleQualifiedItems(files)
                let graph = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: svg)
                let member = try #require(graph.owner(of: "vOnly"), "\(mode)")
                #expect(graph.edgeEnds.filter { $0.hasPrefix("C -> ") } == ["C -> \(member)"], "\(mode)")
                let text = DiagramScript(
                    items: try moduleQualifiedItems(files), configuration: Configuration(elements: elements)
                ).text
                #expect(ClassDiagramIds.lines(of: text, containing: "<|-- C ") == ["Base.V <|-- C : inherits"],
                        "\(mode)")
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
