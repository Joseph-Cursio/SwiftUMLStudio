import Testing
@testable import SwiftUMLBridgeFramework

/// An alias never takes an id that only an edge uses — Mermaid and PlantUML give an edge's
/// undeclared end a node of its own, so the two would be drawn as one (#54).
@Suite("Class-diagram aliases — ids that edges use")
struct ClassDiagramEdgeIdTests {

    @Test("a suffix never takes a supertype that only an inheritance edge names")
    func suffixSkipsUndrawnSupertype() {
        let source = "class A: A0 {}\nextension A {}"
        let mermaid = ClassDiagramIds.script(for: source, format: .mermaid)
        #expect(ClassDiagramIds.mermaid(in: mermaid) == ["A", "A1"])
        #expect(ClassDiagramIds.lines(of: mermaid, containing: "<|--") == ["A0 <|-- A : inherits"])
        #expect(ClassDiagramIds.plantUML(for: source) == ["A", "A1"])
    }

    @Test("a suffix never takes a generic supertype's id, which its edge writes without arguments")
    func suffixSkipsGenericSupertype() {
        let source = "class C: Foo0<Int> {}\nstruct Foo {}\nextension Foo {}"
        let mermaid = ClassDiagramIds.script(for: source, format: .mermaid)
        #expect(ClassDiagramIds.lines(of: mermaid, containing: "<|--") == ["Foo0 <|-- C : inherits"])
        #expect(ClassDiagramIds.mermaid(in: mermaid) == ["C", "Foo", "Foo1"])
        #expect(ClassDiagramIds.plantUML(for: source) == ["C", "Foo", "Foo1"])
    }

    @Test("a suffix never takes a raw type that only an edge names")
    func suffixSkipsRawType() {
        let source = "enum Flags: Int8 { case a }\n" + String(repeating: "extension Int {}\n", count: 10)
        #expect(!ClassDiagramIds.mermaid(for: source).contains("Int8"))
        #expect(!ClassDiagramIds.plantUML(for: source).contains("Int8"))
    }

    @Test("a suffix never takes a hidden protocol that a conformance edge names")
    func suffixSkipsHiddenConformance() {
        let ids = ClassDiagramIds.mermaid(
            for: "protocol Foo0 {}\nstruct S: Foo0 {}\nstruct Foo {}\nextension Foo {}",
            elements: ElementOptions(exclude: ["Foo0"])
        )
        #expect(ids == ["S", "Foo", "Foo1"])
    }

    @Test("a suffix never takes a conformance that only an extension's edge names")
    func suffixSkipsExtensionConformance() {
        let mermaid = ClassDiagramIds.script(for: "struct P {}\nextension P {}\nextension Bar: P0 {}", format: .mermaid)
        #expect(ClassDiagramIds.lines(of: mermaid, containing: "P0 ").count == 1, "\(mermaid)")
        #expect(ClassDiagramIds.mermaid(in: mermaid) == ["P", "P1", "Bar"])
    }

    // MARK: - Nested-type edges

    @Test("PlantUML reserves a hidden parent its nested-type edge names; Mermaid draws no such edge")
    func hiddenNestedParentIsReservedWhereItsEdgeIsDrawn() {
        let source = "fileprivate struct Foo0 { struct Inner {} }\nstruct Foo {}\nextension Foo {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        #expect(ClassDiagramIds.lines(of: plantUML, containing: "+--") == ["Foo0 +-- Foo0.Inner"])
        #expect(ClassDiagramIds.plantUML(in: plantUML).last == "Foo1")
        #expect(ClassDiagramIds.mermaid(for: source).last == "Foo0")
    }

    @Test("a hidden nested parent's short name, which no edge uses, does not shift an alias")
    func hiddenNestedParentShortNameDoesNotShiftAlias() {
        let source = "struct Outer { fileprivate struct Foo0 { struct Inner {} } }\nstruct Foo {}\nextension Foo {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        #expect(ClassDiagramIds.lines(of: plantUML, containing: "+--") == ["Outer.Foo0 +-- Outer.Foo0.Inner"])
        #expect(ClassDiagramIds.plantUML(in: plantUML) == ["Outer", "Outer.Foo0.Inner", "Foo", "Foo0"])
    }

    @Test("a hidden nested parent is reserved under the qualified name its edge uses")
    func hiddenNestedParentReservedUnderEdgeName() {
        let source = "struct Outer { struct Foo {}\n fileprivate struct Foo0 { struct Inner {} } }\n"
            + "extension Outer.Foo {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        #expect(ClassDiagramIds.lines(of: plantUML, containing: "+--").contains("Outer.Foo0 +-- Outer.Foo0.Inner"))
        let ids = ClassDiagramIds.plantUML(in: plantUML)
        #expect(!ids.contains("Outer.Foo0"), "\(ids)")
        #expect(ids.last == "Outer.Foo1")
    }

    @Test("a drawn nested parent's short name does not shift a PlantUML alias")
    func drawnNestedParentShortNameDoesNotShiftAlias() {
        let source = "struct Outer { struct Foo0 { struct Inner {} } }\nstruct Foo {}\nextension Foo {}"
        let plantUML = ClassDiagramIds.script(for: source, format: .plantuml)
        #expect(ClassDiagramIds.lines(of: plantUML, containing: "+--")
            == ["Outer +-- Outer.Foo0", "Outer.Foo0 +-- Outer.Foo0.Inner"])
        #expect(ClassDiagramIds.plantUML(in: plantUML) == ["Outer", "Outer.Foo0", "Outer.Foo0.Inner", "Foo", "Foo0"])
    }

    // MARK: - The edges `linkParents` yields

    @Test("a composition draws one edge per part")
    func compositionDrawsOneEdgePerPart() {
        let script = ClassDiagramIds.script(for: "struct MyType: Sendable & Codable {}", format: .mermaid)
        #expect(ClassDiagramIds.lines(of: script, containing: "<|--")
            == ["Sendable <|-- MyType : inherits", "Codable <|-- MyType : inherits"])
    }

    @Test("a macro-synthesised conformance draws its edge")
    func macroConformanceDrawsEdge() {
        let mermaid = ClassDiagramIds.script(for: "@Model class Item {}", format: .mermaid)
        #expect(ClassDiagramIds.lines(of: mermaid, containing: "<|--")
            == ["Observable <|-- Item : inherits", "PersistentModel <|-- Item : inherits"])
    }
}
