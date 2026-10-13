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

    /// The alias of every PlantUML class declaration: `class "<name>" as <alias> …`.
    private func plantUMLAliases(for source: String) -> [String] {
        text(for: source, Configuration(format: .plantuml))
            .split(separator: "\n")
            .filter { $0.hasPrefix("class \"") }
            .compactMap { line in
                line.range(of: " as ").map { String(line[$0.upperBound...].prefix { $0 != " " }) }
            }
    }

    private func lines(of source: String, format: DiagramFormat, containing marker: String) -> [String] {
        text(for: source, Configuration(format: format))
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains(marker) }
    }

    static let collidingSources = [
        // A repeat's suffix equals a type declared earlier.
        "struct Foo0 {}\nstruct Foo {}\nextension Foo {}",
        // The diagram-wide counter reaches a declared name on the third repeat.
        "struct Vector {}\nstruct Vector2 {}\nextension Vector {}\nextension Vector {}\nextension Vector {}",
        // The suffix equals a name declared only later, by an extension of an undeclared type.
        "struct Foo {}\nextension Foo {}\nextension Foo0 {}",
        // The suffix equals a type declared after the repeat.
        "struct Foo {}\nstruct Foo {}\nstruct Foo0 {}"
    ]

    @Test("Mermaid never declares two classes under one id", arguments: collidingSources)
    func mermaidIdsAreDistinct(source: String) {
        let ids = mermaidIds(for: source)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test("PlantUML never declares two classes under one alias", arguments: collidingSources)
    func plantUMLAliasesAreDistinct(source: String) {
        let aliases = plantUMLAliases(for: source)
        #expect(Set(aliases).count == aliases.count, "duplicate aliases: \(aliases)")
    }

    @Test("a colliding extension takes the next free suffix, and its edge follows")
    func collidingExtensionSkipsTakenSuffix() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo {}"
        #expect(mermaidIds(for: source) == ["Foo0", "Foo", "Foo1"])
        #expect(lines(of: source, format: .mermaid, containing: "<..") == ["Foo <.. Foo1 : ext"])
        #expect(lines(of: source, format: .plantuml, containing: "<..") == ["Foo <.. Foo1 : ext"])
    }

    @Test("a type nested in a colliding extension attaches to the extension's own id")
    func nestedTypeAttachesToExtensionAlias() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo { struct Inner {} }"
        #expect(lines(of: source, format: .plantuml, containing: "+--") == ["Foo1 +-- Foo.Inner"])
    }

    @Test("aliases skip only taken candidates; the counter stays diagram-wide")
    func counterSkipsOnlyTakenCandidates() {
        let source = "struct Vector {}\nstruct Vector2 {}\n"
            + String(repeating: "extension Vector {}\n", count: 4)
        #expect(mermaidIds(for: source) == ["Vector", "Vector2", "Vector0", "Vector1", "Vector3", "Vector4"])
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
}
