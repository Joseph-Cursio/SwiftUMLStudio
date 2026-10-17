import Testing
@testable import SwiftUMLBridgeFramework

/// The SVG class diagram draws exactly the types the PlantUML, Mermaid and Nomnoml ones draw (#74).
/// `LayoutGraphBuilder` kept every processable kind, so `showExtensions: .none`,
/// `elements.exclude` and `elements.havingAccessLevel`, which the default sets to leave out
/// `fileprivate`, never hid anything in SVG.
@Suite("SVG class diagram — element filters")
struct SVGClassDiagramFilterTests {

    private func svg(_ source: String, _ elements: ElementOptions) -> LayoutGraph? {
        ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(elements: elements, format: .svg)).layoutGraph
    }

    /// Each SVG node as `id<<stereotype>>`, in drawing order.
    private func svgNodes(_ source: String, _ elements: ElementOptions) -> [String] {
        svg(source, elements)?.nodes.map { "\($0.id)<<\($0.stereotype ?? "")>>" } ?? []
    }

    // MARK: - The Issue's Cases

    @Test("showExtensions .none draws no extension node")
    func noneHidesExtensions() {
        let hidden = ElementOptions(showExtensions: ExtensionVisualization.none)
        #expect(svgNodes("struct Foo {}\nextension Foo {}", hidden) == ["Foo<<struct>>"])
    }

    @Test("showExtensions .none also drops the hidden extension's conformance edge")
    func noneHidesExtensionEdges() {
        let source = "protocol P {}\nstruct Foo {}\nextension Foo: P { func bar() {} }"
        let graph = svg(source, ElementOptions(showExtensions: ExtensionVisualization.none))
        #expect(graph?.nodes.map(\.id) == ["P", "Foo"])
        #expect(graph?.edgeEnds == [])
    }

    @Test("elements.exclude drops the excluded type")
    func excludeHidesType() {
        let nodes = svgNodes("class InternalCache {}\nclass PublicAPI {}", ElementOptions(exclude: ["Internal*"]))
        #expect(nodes == ["PublicAPI<<class>>"])
    }

    @Test("havingAccessLevel drops types declared below the listed levels")
    func accessLevelHidesType() {
        let publicOnly = ElementOptions(havingAccessLevel: [.open, .public])
        #expect(svgNodes("public class Visible {}\nclass Hidden: Visible {}", publicOnly) == ["Visible<<class>>"])
    }

    @Test("the default configuration hides a fileprivate type, as the text formats do")
    func defaultHidesFileprivate() {
        #expect(svgNodes("fileprivate struct Secret {}\nstruct Shown {}", ElementOptions()) == ["Shown<<struct>>"])
    }

    // MARK: - Hidden Types and Their Edges

    /// The text formats still write the edge, and their renderers draw an empty box for its
    /// undeclared end. SVG draws no box for a type it does not declare, as for `Codable`, so the
    /// edge goes with the excluded type.
    @Test("an edge to an excluded supertype is not drawn")
    func edgeToExcludedSupertype() {
        let source = "class InternalCache {}\nclass PublicAPI: InternalCache {}"
        let graph = svg(source, ElementOptions(exclude: ["Internal*"]))
        #expect(graph?.nodes.map(\.id) == ["PublicAPI"])
        #expect(graph?.edgeEnds == [])
    }

    /// A hidden type has no box to merge into, so its extension keeps its own and stands in for
    /// it, as when extensions are drawn apart (#153).
    @Test("merged: a hidden type's extension stands in for it")
    func mergedExtensionOfHiddenTypeStandsIn() {
        let source = "fileprivate struct Foo {}\nextension Foo { func bar() {} }\nstruct Shown {}"
        #expect(svgNodes(source, ElementOptions(showExtensions: .merged)) == ["Shown<<struct>>", "Foo<<extension>>"])
    }

    /// The access-level filter skips extensions, so a hidden type's extension is still drawn and
    /// stands in for it, as in the text formats.
    @Test("an edge to a hidden type ends on that type's extension")
    func edgeToHiddenTypeEndsOnExtension() {
        let graph = svg("fileprivate class Base {}\nextension Base {}\nclass Sub: Base {}", ElementOptions())
        #expect(graph?.nodes.map { "\($0.id)<<\($0.stereotype ?? "")>>" } == ["Sub<<class>>", "Base<<extension>>"])
        #expect(graph?.edgeEnds == ["Sub -> Base"])
    }

    @Test("a hidden type's nested types hang off its extension")
    func nestedTypesOfHiddenParent() {
        let graph = svg("fileprivate struct Outer { struct Inner {} }\nextension Outer {}", ElementOptions())
        #expect(graph?.nodes.map { "\($0.id)<<\($0.stereotype ?? "")>>" } == [
            "Outer.Inner<<struct>>", "Outer<<extension>>"
        ])
        #expect(graph?.edgeEnds == ["Outer -> Outer.Inner"])
    }

    // MARK: - Parity With the Text Formats

    /// Each type Mermaid declares, as `label<<stereotype>>`, sorted: `class <id>["<label>"] {`
    /// followed by `<<stereotype>>`.
    private func mermaidTypes(_ source: String, _ elements: ElementOptions) -> [String] {
        let text = ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(elements: elements, format: .mermaid)).text
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var types: [String] = []
        for (index, line) in lines.enumerated() where line.hasPrefix("class ") {
            guard let open = line.range(of: "[\""), let close = line.range(of: "\"]") else { continue }
            let label = line[open.upperBound..<close.lowerBound]
            let stereotype = lines.indices.contains(index + 1) && lines[index + 1].hasPrefix("<<")
                ? lines[index + 1] : "<<>>"
            types.append("\(label)\(stereotype)")
        }
        return types.sorted()
    }

    private func svgTypes(_ source: String, _ elements: ElementOptions) -> [String] {
        (svg(source, elements)?.nodes.map { "\($0.label)<<\($0.stereotype ?? "")>>" } ?? []).sorted()
    }

    static let paritySources = [
        "struct Foo {}\nextension Foo {}\nprotocol P {}\nextension Foo: P {}",
        "public class Visible {}\nclass Hidden: Visible {}\nfileprivate struct Secret {}\nprivate class Private {}",
        "class InternalCache {}\nclass PublicAPI: InternalCache {}\nstruct InternalThing {}",
        "fileprivate struct Outer { struct Inner {} }\nextension Outer {}\npublic struct Box { struct Lid {} }",
        "fileprivate class Base {}\nextension Base { func run() {} }\nclass Sub: Base {}"
    ]

    static let parityOptions: [ElementOptions] = [
        ElementOptions(),
        ElementOptions(showExtensions: ExtensionVisualization.none),
        ElementOptions(showExtensions: .merged),
        ElementOptions(exclude: ["Internal*", "Lid"]),
        ElementOptions(havingAccessLevel: [.open, .public]),
        ElementOptions(havingAccessLevel: [.open, .public, .internal, .fileprivate, .private])
    ]

    @Test("SVG draws the types Mermaid declares", arguments: paritySources.indices, parityOptions.indices)
    func svgMatchesMermaid(source: Int, options: Int) {
        let text = Self.paritySources[source]
        let elements = Self.parityOptions[options]
        #expect(svgTypes(text, elements) == mermaidTypes(text, elements), "\(text) with options \(options)")
    }
}
