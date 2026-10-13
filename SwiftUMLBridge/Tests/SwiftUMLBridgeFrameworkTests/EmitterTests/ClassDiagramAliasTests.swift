import Testing
@testable import SwiftUMLBridgeFramework

/// No two elements of a Mermaid or PlantUML class diagram are declared under one id (#54).
@Suite("Class-diagram aliases — distinct declared ids")
struct ClassDiagramAliasTests {

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
        let ids = ClassDiagramIds.mermaid(for: source)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test("PlantUML never declares two classes under one id", arguments: collidingSources)
    func plantUMLIdsAreDistinct(source: String) {
        let ids = ClassDiagramIds.plantUML(for: source)
        #expect(Set(ids).count == ids.count, "duplicate ids: \(ids)")
    }

    @Test("a colliding extension takes the next free suffix, and its edge follows")
    func collidingExtensionSkipsTakenSuffix() {
        let source = "struct Foo0 {}\nstruct Foo {}\nextension Foo {}"
        #expect(ClassDiagramIds.mermaid(for: source) == ["Foo0", "Foo", "Foo1"])
        for format in [DiagramFormat.mermaid, .plantuml] {
            let script = ClassDiagramIds.script(for: source, format: format)
            #expect(ClassDiagramIds.lines(of: script, containing: "<..") == ["Foo <.. Foo1 : ext"])
        }
    }

    @Test("consecutive taken suffixes are all skipped")
    func consecutiveTakenSuffixesAreSkipped() {
        #expect(ClassDiagramIds.mermaid(for: "struct Foo0 {}\nstruct Foo1 {}\nstruct Foo {}\nextension Foo {}")
            == ["Foo0", "Foo1", "Foo", "Foo2"])
    }

    @Test("a type nested in a colliding extension attaches to the extension's own id")
    func nestedTypeAttachesToExtensionAlias() {
        let script = ClassDiagramIds.script(
            for: "struct Foo0 {}\nstruct Foo {}\nextension Foo { struct Inner {} }", format: .plantuml
        )
        #expect(ClassDiagramIds.lines(of: script, containing: "+--") == ["Foo1 +-- Foo.Inner"])
    }

    // MARK: - Aliases that must not move

    @Test("aliases skip only taken candidates; the counter stays diagram-wide")
    func counterSkipsOnlyTakenCandidates() {
        let source = "struct Vector {}\nstruct Vector2 {}\n"
            + String(repeating: "extension Vector {}\n", count: 4)
        #expect(ClassDiagramIds.mermaid(for: source)
            == ["Vector", "Vector2", "Vector0", "Vector1", "Vector3", "Vector4"])
    }

    @Test("two repeated names share one diagram-wide counter")
    func counterIsSharedAcrossNames() {
        #expect(ClassDiagramIds.mermaid(for: "struct A {}\nstruct B {}\nextension A {}\nextension B {}")
            == ["A", "B", "A0", "B1"])
    }

    @Test("a diagram with no collision keeps its aliases")
    func noCollisionKeepsAliases() {
        #expect(ClassDiagramIds.mermaid(for: "struct Foo {}\nextension Foo {}") == ["Foo", "Foo0"])
    }

    @Test("a hidden type's name does not shift an alias")
    func hiddenTypeDoesNotReserveItsName() {
        let ids = ClassDiagramIds.mermaid(
            for: "struct Foo0 {}\nstruct Foo {}\nextension Foo {}",
            elements: ElementOptions(exclude: ["Foo0"])
        )
        #expect(ids == ["Foo", "Foo0"])
    }

    @Test("merged: a hidden type that absorbed an extension does not shift an alias")
    func mergedHiddenTypeDoesNotReserveItsName() {
        let ids = ClassDiagramIds.mermaid(
            for: "fileprivate struct Foo0 {}\nextension Foo0 {}\nstruct Foo {}\nstruct Foo {}",
            elements: ElementOptions(showExtensions: .merged)
        )
        #expect(ids == ["Foo", "Foo0"])
    }

    @Test("a nested type's short name does not shift an alias")
    func nestedShortNameDoesNotShiftAlias() {
        #expect(ClassDiagramIds.mermaid(for: "struct Outer { struct Foo0 {} }\nstruct Foo {}\nextension Foo {}")
            == ["Outer", "Outer.Foo0", "Foo", "Foo0"])
    }

    // MARK: - Macros

    /// The parser produces no macro items today, so these are built directly.
    private static let macroItems = [
        SyntaxStructure(kind: .struct, name: "Foo"),
        SyntaxStructure(kind: .struct, name: "Foo"),
        SyntaxStructure(kind: .macro, name: "Foo0")
    ]

    @Test("a macro's PlantUML note id is never taken by a suffix")
    func macroNoteIdIsReserved() {
        let script = DiagramScript(items: Self.macroItems, configuration: Configuration(format: .plantuml)).text
        #expect(ClassDiagramIds.plantUML(in: script) == ["Foo", "Foo1", "Foo0"])
    }

    @Test("a Mermaid macro is only a comment, so its name does not shift an alias")
    func mermaidMacroDoesNotReserveItsName() {
        let script = DiagramScript(items: Self.macroItems, configuration: Configuration(format: .mermaid)).text
        #expect(ClassDiagramIds.mermaid(in: script) == ["Foo", "Foo0"])
        #expect(ClassDiagramIds.lines(of: script, containing: "%% macro") == ["%% macro: Foo0 (Foo0)"])
    }
}
