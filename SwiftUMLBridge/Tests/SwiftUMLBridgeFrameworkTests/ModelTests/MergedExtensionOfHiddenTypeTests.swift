import Testing
@testable import SwiftUMLBridgeFramework

/// `showExtensions: .all` draws an extension of a type the diagram hides as a box of its own, which
/// stands in for that type (#74). `.merged` used to merge it into the hidden type instead, so its
/// members, the conformances it declares and the types nested in it lost their box with that type
/// (#153). Now a hidden type's first drawn extension stands in for it under `.merged` too.
@Suite("Merged extensions of a type the diagram hides")
struct MergedExtensionOfHiddenTypeTests {

    private static let publicOnly: [AccessLevel] = [.open, .public]
    private static let noPrivate: [AccessLevel] = [.open, .public, .package, .internal]

    /// What an SVG class diagram draws: each node as `id<<stereotype>>: members`, then each edge.
    private func drawn(_ graph: LayoutGraph?) -> [String] {
        guard let graph else { return ["no layout graph"] }
        let nodes = graph.nodes.map { node in
            "\(node.id)<<\(node.stereotype ?? "")>>: \(node.compartments.flatMap(\.items).joined(separator: ", "))"
        }
        return nodes + graph.edgeEnds
    }

    /// Each source has one extension of a type the diagram hides, so `.merged` has nothing to fold
    /// into it and should draw exactly what `.all` draws.
    static let oneExtensionOfAHiddenType: [(source: String, access: [AccessLevel])] = [
        // fileprivate, which the default levels leave out
        ("protocol P {}\nfileprivate struct Foo {}\nextension Foo: P { func f() {} }",
         ElementOptions.defaultAccessLevels),
        // private, under levels that leave it out
        ("protocol P {}\nprivate struct Foo {}\nextension Foo: P { func f() {} }", noPrivate),
        // internal, in a public-only diagram
        ("public protocol P {}\nstruct Foo {}\nextension Foo: P { public func f() {} }", publicOnly),
        // a hidden nested type
        ("protocol P {}\nstruct Outer { fileprivate struct Inner {} }\nextension Outer.Inner: P { func f() {} }",
         ElementOptions.defaultAccessLevels),
        // a type nested in the extension
        ("protocol P {}\nfileprivate struct Foo {}\nextension Foo: P {\n    struct Inner {}\n    func f() {}\n}",
         ElementOptions.defaultAccessLevels),
        // an edge to the hidden type, which ends on its extension
        ("fileprivate protocol Base {}\nextension Base { func run() {} }\nstruct Sub: Base {}",
         ElementOptions.defaultAccessLevels),
        // a hidden type's own nested type, which hangs off its extension
        ("fileprivate struct Outer { struct Inner {} }\nextension Outer {}", ElementOptions.defaultAccessLevels)
    ]

    @Test("PlantUML, Mermaid and Nomnoml: .merged writes what .all writes",
          arguments: oneExtensionOfAHiddenType.indices, [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func textFormatsMatchAll(index: Int, format: DiagramFormat) {
        let (source, access) = Self.oneExtensionOfAHiddenType[index]
        #expect(classDiagram(source, format, .merged, access: access).text
            == classDiagram(source, format, .all, access: access).text)
    }

    @Test("SVG: .merged draws what .all draws", arguments: oneExtensionOfAHiddenType.indices)
    func svgMatchesAll(index: Int) {
        let (source, access) = Self.oneExtensionOfAHiddenType[index]
        #expect(drawn(classDiagram(source, .svg, .merged, access: access).layoutGraph)
            == drawn(classDiagram(source, .svg, .all, access: access).layoutGraph))
    }

    /// Two extensions of one hidden type: one box, the first extension's, as for a type the
    /// sources only extend.
    @Test("a hidden type's extensions share its first extension's box")
    func extensionsShareTheFirstBox() {
        let source = """
            protocol P {}
            protocol Q {}
            fileprivate struct Foo {}
            extension Foo: P { func f() {} }
            extension Foo: Q { func g() {} }
            """
        #expect(drawn(classDiagram(source, .svg, .merged).layoutGraph) == [
            "P<<protocol>>: ", "Q<<protocol>>: ", "Foo<<extension>>: ~ f(), ~ g()", "Foo -> P", "Foo -> Q"
        ])
        let plantUML = classDiagram(source, .plantuml, .merged).text
        #expect(plantUML.contains("class \"Foo\" as Foo << (X, orchid) extension >> { \n  ~f\n  ~g \n}"), "\(plantUML)")
        #expect(plantUML.contains("P <|.. Foo : conforms to"))
        #expect(plantUML.contains("Q <|.. Foo : conforms to"))
    }

    // MARK: - Guards

    @Test("a drawn type still takes its extension's members")
    func drawnTypeStillMerges() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P { func f() {} }"
        #expect(drawn(classDiagram(source, .svg, .merged).layoutGraph).prefix(2)
            == ["P<<protocol>>: ", "Foo<<struct>>: ~ f()"])
        #expect(classDiagram(source, .plantuml, .merged).text.contains("~f <&bolt>"))
    }

    @Test("an extension the diagram excludes with its type stays out")
    func excludedExtensionStaysOut() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P { func f() {} }"
        for mode in [ExtensionVisualization.all, .merged] {
            #expect(
                drawn(classDiagram(source, .svg, mode, exclude: ["Foo"]).layoutGraph) == ["P<<protocol>>: "], "\(mode)"
            )
            #expect(!classDiagram(source, .plantuml, mode, exclude: ["Foo"]).text.contains("Foo"), "\(mode)")
        }
    }
}
