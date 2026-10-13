import Testing
@testable import SwiftUMLBridgeFramework

/// Class-diagram ids come from `DiagramContext.uniqName`: Mermaid declares `class <alias>[…]`
/// and PlantUML `class "<name>" as <alias>`, so two elements sharing an alias are drawn as one.
@Suite("Class-diagram aliases — distinct ids")
struct ClassDiagramAliasTests {

    private func text(for source: String, _ configuration: Configuration) -> String {
        ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// The id of every Mermaid class declaration: `class <id>["<label>"] {`.
    private func mermaidIds(for source: String, elements: ElementOptions = ElementOptions()) -> [String] {
        text(for: source, Configuration(elements: elements, format: .mermaid))
            .split(separator: "\n")
            .filter { $0.hasPrefix("class ") }
            .map { String($0.dropFirst("class ".count).prefix { $0 != "[" }) }
    }

    /// Every id a PlantUML script declares: `class "<name>" as <id><generics> …` and `note as <id>`.
    private func plantUMLIds(in script: String) -> [String] {
        script.split(separator: "\n").compactMap { line -> String? in
            if line.hasPrefix("note as ") {
                return String(line.dropFirst("note as ".count).prefix { $0 != " " })
            }
            guard line.hasPrefix("class \""), let range = line.range(of: " as ") else { return nil }
            return String(line[range.upperBound...].prefix { $0 != " " && $0 != "<" })
        }
    }

    private func plantUMLIds(for source: String, elements: ElementOptions = ElementOptions()) -> [String] {
        plantUMLIds(in: text(for: source, Configuration(elements: elements, format: .plantuml)))
    }

    private func lines(
        of source: String,
        format: DiagramFormat,
        elements: ElementOptions = ElementOptions(),
        containing marker: String
    ) -> [String] {
        text(for: source, Configuration(elements: elements, format: format))
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains(marker) }
    }

    static let collidingSources = [
        // A repeat's suffix equals a type declared earlier.
        "struct Foo0 {}\nstruct Foo {}\nextension Foo {}",
        // The same, with the declared type generic: PlantUML's id stops at the `<`.
        "struct Foo0<T> {}\nstruct Foo {}\nextension Foo {}",
        // The diagram-wide counter reaches a declared name on the third repeat.
        "struct Vector {}\nstruct Vector2 {}\nextension Vector {}\nextension Vector {}\nextension Vector {}",
        // Two suffixes in a row are taken.
        "struct Foo0 {}\nstruct Foo1 {}\nstruct Foo {}\nextension Foo {}",
        // The suffix equals a name declared only later, by an extension of an undeclared type.
        "struct Foo {}\nextension Foo {}\nextension Foo0 {}",
        // The suffix equals a type declared after the repeat.
        "struct Foo {}\nstruct Foo {}\nstruct Foo0 {}",
        // The suffix equals a nested type's full name.
        "struct P { struct Q {} }\nextension P { struct Q {} }\nextension P { struct Q0 {} }",
        // Two base names reach the same suffixed alias: X1 + 0 and, later, X + 10.
        "struct X1 {}\nstruct X {}\nextension X1 {}\n" + String(repeating: "extension X {}\n", count: 9)
    ]

    @Test("Mermaid never declares two classes under one id", arguments: collidingSources)
    func mermaidIdsAreDistinct(source: String) {
        let ids = mermaidIds(for: source)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test("PlantUML never declares two classes under one id", arguments: collidingSources)
    func plantUMLIdsAreDistinct(source: String) {
        let ids = plantUMLIds(for: source)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test("a colliding extension takes the next free suffix, and its edge follows")
    func collidingExtensionSkipsTakenSuffix() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo {}"
        #expect(mermaidIds(for: source) == ["Foo0", "Foo", "Foo1"])
        #expect(lines(of: source, format: .mermaid, containing: "<..") == ["Foo <.. Foo1 : ext"])
        #expect(lines(of: source, format: .plantuml, containing: "<..") == ["Foo <.. Foo1 : ext"])
    }

    @Test("consecutive taken suffixes are all skipped")
    func consecutiveTakenSuffixesAreSkipped() {
        #expect(mermaidIds(for: "struct Foo0 {}\nstruct Foo1 {}\nstruct Foo {}\nextension Foo {}")
            == ["Foo0", "Foo1", "Foo", "Foo2"])
    }

    @Test("a type nested in a colliding extension attaches to the extension's own id")
    func nestedTypeAttachesToExtensionAlias() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo { struct Inner {} }"
        #expect(lines(of: source, format: .plantuml, containing: "+--") == ["Foo1 +-- Foo.Inner"])
    }

    // MARK: - Ids that only an edge declares

    @Test("a suffix never takes a supertype that only an inheritance edge names")
    func suffixSkipsUndrawnSupertype() {
        let source = "class A: A0 {}\nextension A {}"
        #expect(mermaidIds(for: source) == ["A", "A1"])
        #expect(lines(of: source, format: .mermaid, containing: "<|--") == ["A0 <|-- A : inherits"])
        #expect(plantUMLIds(for: source) == ["A", "A1"])
    }

    @Test("a suffix never takes a raw type that only an edge names")
    func suffixSkipsRawType() {
        let source = "enum Flags: Int8 { case a }\n" + String(repeating: "extension Int {}\n", count: 10)
        #expect(!mermaidIds(for: source).contains("Int8"))
        #expect(!plantUMLIds(for: source).contains("Int8"))
    }

    @Test("a suffix never takes a hidden protocol that a conformance edge names")
    func suffixSkipsHiddenConformance() {
        let source = "protocol Foo0 {}\nstruct S: Foo0 {}\nstruct Foo {}\nextension Foo {}"
        #expect(mermaidIds(for: source, elements: ElementOptions(exclude: ["Foo0"])) == ["S", "Foo", "Foo1"])
    }

    @Test("PlantUML reserves a hidden parent its nested-type edge names; Mermaid draws no such edge")
    func hiddenNestedParentIsReservedWhereItsEdgeIsDrawn() {
        let source = "fileprivate struct Foo0 { struct Inner {} }\nstruct Foo {}\nextension Foo {}"
        #expect(lines(of: source, format: .plantuml, containing: "+--") == ["Foo0 +-- Foo0.Inner"])
        #expect(plantUMLIds(for: source).last == "Foo1")
        #expect(mermaidIds(for: source).last == "Foo0")
    }

    // MARK: - Aliases that must not move

    @Test("aliases skip only taken candidates; the counter stays diagram-wide")
    func counterSkipsOnlyTakenCandidates() {
        let source = "struct Vector {}\nstruct Vector2 {}\n"
            + String(repeating: "extension Vector {}\n", count: 4)
        #expect(mermaidIds(for: source) == ["Vector", "Vector2", "Vector0", "Vector1", "Vector3", "Vector4"])
    }

    @Test("two repeated names share one diagram-wide counter")
    func counterIsSharedAcrossNames() {
        #expect(mermaidIds(for: "struct A {}\nstruct B {}\nextension A {}\nextension B {}") == ["A", "B", "A0", "B1"])
    }

    @Test("a diagram with no collision keeps its aliases")
    func noCollisionKeepsAliases() {
        #expect(mermaidIds(for: "struct Foo {}\nextension Foo {}") == ["Foo", "Foo0"])
    }

    @Test("a hidden type's name does not shift an alias")
    func hiddenTypeDoesNotReserveItsName() {
        let ids = mermaidIds(
            for: "struct Foo0 {}\nstruct Foo {}\nextension Foo {}",
            elements: ElementOptions(exclude: ["Foo0"])
        )
        #expect(ids == ["Foo", "Foo0"])
    }

    @Test("merged: a hidden type that absorbed an extension does not shift an alias")
    func mergedHiddenTypeDoesNotReserveItsName() {
        let ids = mermaidIds(
            for: "fileprivate struct Foo0 {}\nextension Foo0 {}\nstruct Foo {}\nstruct Foo {}",
            elements: ElementOptions(showExtensions: .merged)
        )
        #expect(ids == ["Foo", "Foo0"])
    }

    @Test("a nested type's short name does not shift an alias")
    func nestedShortNameDoesNotShiftAlias() {
        #expect(mermaidIds(for: "struct Outer { struct Foo0 {} }\nstruct Foo {}\nextension Foo {}")
            == ["Outer", "Outer.Foo0", "Foo", "Foo0"])
    }

    // MARK: - Macros

    @Test("a macro's PlantUML note id is never taken by a suffix")
    func macroNoteIdIsReserved() {
        // The parser produces no macro items today, so build them directly.
        let items = [
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(kind: .struct, name: "Foo"),
            SyntaxStructure(kind: .macro, name: "Foo0")
        ]
        let script = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        #expect(plantUMLIds(in: script) == ["Foo", "Foo1", "Foo0"])
    }
}
