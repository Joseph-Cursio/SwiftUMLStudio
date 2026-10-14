import Testing
@testable import SwiftUMLBridgeFramework

/// `extension Foo<Int>` is drawn as an extension of `Foo` (#66), with the arguments it binds shown
/// beside the name while `showGenerics` is on, as a generic type's own parameters are. They are
/// display only: ids, edges, merging and exclusion never see them.
@Suite("Class diagram: the arguments a bound extension shows")
struct BoundGenericArgumentDisplayTests {

    private static let bound = "struct Foo<T> {}\nextension Foo<Int> {}"

    private func svgLabels(_ source: String, _ elements: ElementOptions = ElementOptions()) -> [String] {
        let configuration = Configuration(elements: elements, format: .svg)
        let graph = ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
        return graph?.nodes.map { "\($0.id)=\($0.label)" } ?? []
    }

    @Test("PlantUML writes them as the alias's generic part, the shape of `as Foo<T>`")
    func plantUMLGenericPart() {
        let script = ClassDiagramIds.script(for: Self.bound, format: .plantuml)
        #expect(script.contains("class \"Foo\" as Foo0<Int> << (X, orchid) extension >> {"), "\(script)")
        #expect(ClassDiagramIds.plantUML(in: script) == ["Foo", "Foo0"])
    }

    /// Mermaid drops a raw `<Int>` from a label and reads it after the stereotype as a member;
    /// the bundled Mermaid 11.14.0 renders `Foo&lt;Int&gt;` as `Foo<Int>`.
    @Test("Mermaid writes them into the label as entities, not after the stereotype")
    func mermaidLabel() {
        let script = ClassDiagramIds.script(for: Self.bound, format: .mermaid)
        #expect(script.contains("class Foo0[\"Foo&lt;Int&gt;\"] {\n    <<extension>>\n}"), "\(script)")
    }

    @Test("Nomnoml writes them after the name, as a type's parameters")
    func nomnomlHeader() {
        let script = ClassDiagramIds.script(for: Self.bound, format: .nomnoml)
        #expect(script.contains("[<extension> Foo <Int>]"), "\(script)")
    }

    @Test("SVG and Studio's canvas label the node with them")
    func svgLabel() {
        #expect(svgLabels(Self.bound) == ["Foo=Foo", "Foo_1=Foo<Int>"])
    }

    @Test("sugar shows as the type it stands for", arguments: [
        ("extension [Int] {}", "as Array<Int> ", "[\"Array&lt;Int&gt;\"]", "[<extension> Array <Int>]"),
        ("extension Int? {}", "as Optional<Int> ", "[\"Optional&lt;Int&gt;\"]", "[<extension> Optional <Int>]"),
        (
            "extension [String: Int] {}", "as Dictionary<String, Int> ",
            "[\"Dictionary&lt;String, Int&gt;\"]", "[<extension> Dictionary <String, Int>]"
        ),
        ("extension [[Int]] {}", "as Array<[Int]> ", "[\"Array&lt;[Int]&gt;\"]", "[<extension> Array <(Int)>]")
    ])
    func sugar(source: String, plantUML: String, mermaid: String, nomnoml: String) {
        #expect(ClassDiagramIds.script(for: source, format: .plantuml).contains(plantUML))
        #expect(ClassDiagramIds.script(for: source, format: .mermaid).contains(mermaid))
        #expect(ClassDiagramIds.script(for: source, format: .nomnoml).contains(nomnoml))
    }

    /// PlantUML's generic part ends at the first `>`; Mermaid and Nomnoml take `->` as it is.
    @Test("a function type's arrow does not end PlantUML's generic part")
    func functionTypeArgument() {
        let source = "extension [() -> Void] {}\nextension [String: (Int) -> Void] {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        #expect(plantUML.contains("class \"Array\" as Array<() → Void> << (X, orchid) extension >> {"), "\(plantUML)")
        #expect(plantUML.contains("as Dictionary<String, (Int) → Void> <<"), "\(plantUML)")
        let mermaid = ClassDiagramIds.script(for: source, format: .mermaid)
        #expect(mermaid.contains("class Array[\"Array&lt;() -&gt; Void&gt;\"]"), "\(mermaid)")
    }

    @Test("with showGenerics off, no format shows them", arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func showGenericsHidesThem(format: DiagramFormat) {
        let elements = ElementOptions(showGenerics: false)
        let script = ClassDiagramIds.script(for: Self.bound, format: format, elements: elements)
        #expect(!script.contains("Int"), "\(script)")
        #expect(svgLabels(Self.bound, elements) == ["Foo=Foo", "Foo_1=Foo"])
    }

    @Test("a merged box shows them only while every extension in it binds the same ones", arguments: [
        ("extension Array<Int> { func one() {} }\nextension Array<String> { func two() {} }", ["Array=Array"]),
        ("extension Array<Int> { func one() {} }\nextension Array<Int> { func two() {} }", ["Array=Array<Int>"]),
        ("extension Array<Int> { func one() {} }\nextension Array { func two() {} }", ["Array=Array"]),
        ("struct Foo<T> {}\nextension Foo<Int> { func one() {} }", ["Foo=Foo"])
    ])
    func mergedLabel(source: String, labels: [String]) {
        #expect(svgLabels(source, ElementOptions(showExtensions: .merged)) == labels)
    }
}
