import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// An extension's `ext` edge ends on the type it extends: the drawn type its name means where it
/// is written, the one `--merge-extensions` merges it into. `uniqName` matched the extension's
/// full name against each drawn type's short name instead, so `extension Outer.Inner` got no edge
/// and a second `extension Foo` got one to the first whenever a nested `Bar.Foo` was drawn (#72).
@Suite("Class-diagram extension edges")
struct ExtensionEdgeTargetTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]

    /// Each `ext` edge of a PlantUML, Mermaid or Nomnoml script, written for `format`.
    private func extEdges(_ script: String, _ format: DiagramFormat) -> [String] {
        let marker = format == .nomnoml ? "] --> " : " <.. "
        return script.split(separator: "\n").map(String.init).filter { $0.contains(marker) }
    }

    /// The `ext` edge from the extension declared as `alias` to the type declared as `type`.
    private func edge(_ type: String, _ alias: String, _ format: DiagramFormat) -> String {
        format == .nomnoml ? "[\(alias)] --> ext [\(type)]" : "\(type) <.. \(alias) : ext"
    }

    private func extEdges(of source: String, _ format: DiagramFormat) -> [String] {
        extEdges(ClassDiagramIds.script(for: source, format: format), format)
    }

    private func extEdges(of items: [SyntaxStructure], _ format: DiagramFormat) -> [String] {
        extEdges(DiagramScript(items: items, configuration: Configuration(format: format)).text, format)
    }

    private func declared(
        _ kind: ElementKind, _ name: String, in file: String, module: String? = nil,
        access: ElementAccessibility? = nil
    ) -> SyntaxStructure {
        let item = SyntaxStructure(accessibility: access, kind: kind, name: name)
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    // MARK: - The issue's witnesses

    @Test("an extension of a nested type, written qualified, is linked to that type", arguments: formats)
    func qualifiedExtensionOfNestedType(format: DiagramFormat) {
        let edges = extEdges(of: "struct Outer { struct Inner {} }\nextension Outer.Inner {}", format)
        #expect(edges == [edge("Outer.Inner", "Outer.Inner0", format)])
    }

    @Test("a nested type of the same short name is not what a top-level extension extends", arguments: formats)
    func nestedShortNameIsNotTheExtendedType(format: DiagramFormat) {
        #expect(extEdges(of: "struct Bar { struct Foo {} }\nextension Foo {}\nextension Foo {}", format).isEmpty)
        let theme = "struct Theme { struct Color {} }\nextension Color {}\nextension Color {}"
        #expect(extEdges(of: theme, format).isEmpty)
    }

    @Test("controls: a type's extension is linked, an outside type's extensions are not", arguments: formats)
    func controls(format: DiagramFormat) {
        #expect(extEdges(of: "struct Inner {}\nextension Inner {}", format) == [edge("Inner", "Inner0", format)])
        #expect(extEdges(of: "extension Foo {}\nextension Foo {}", format).isEmpty)
    }

    /// `TestData/nestedTypes.txt` holds the only qualified extensions among the fixtures.
    @Test("each qualified extension in the nested-types fixture is linked to its type", arguments: formats)
    func nestedTypesFixture(format: DiagramFormat) throws {
        let fixture = try #require(Bundle.module.resourceURL?.appending(path: "TestData/nestedTypes.txt"))
        let edges = extEdges(of: try String(contentsOf: fixture, encoding: .utf8), format)
        #expect(edges == [
            edge("APublic.BPublic", "APublic.BPublic0", format),
            edge("APublic.BPublic", "APublic.BPublic1", format),
            edge("APublic.BPublic.CPublic", "APublic.BPublic.CPublic2", format),
            edge("APublic.BPublic.CInternal", "APublic.BPublic.CInternal3", format)
        ])
    }

    // MARK: - Which type of a name

    /// `public struct Foo` in A.swift (ModA) and in B.swift (ModB), then `extension Foo` in
    /// C.swift (ModB): Swift finds ModB's `Foo`, which `--merge-extensions` merges it into (#107).
    @Test("with two types of a name, the edge goes to the one in the extension's module", arguments: formats)
    func sameModuleType(format: DiagramFormat) {
        let items = [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", access: .public),
            declared(.struct, "Foo", in: "B.swift", module: "ModB", access: .public),
            declared(.extension, "Foo", in: "C.swift", module: "ModB")
        ]
        #expect(extEdges(of: items, format) == [edge("Foo0", "Foo1", format)])
    }

    /// The default access levels leave out `fileprivate`, so B.swift's `Foo` is hidden, and an
    /// extension in B.swift extends it, not A.swift's drawn `Foo`. One in C.swift can't see it.
    @Test("an extension of a hidden type gets no edge to a drawn type of its name", arguments: formats)
    func hiddenType(format: DiagramFormat) {
        let types = [
            declared(.struct, "Foo", in: "A.swift"),
            declared(.struct, "Foo", in: "B.swift", access: .fileprivate)
        ]
        let sameFile = types + [declared(.extension, "Foo", in: "B.swift")]
        #expect(extEdges(of: sameFile, format).isEmpty)
        let otherFile = types + [declared(.extension, "Foo", in: "C.swift")]
        #expect(extEdges(of: otherFile, format) == [edge("Foo", "Foo0", format)])
    }

    @Test("nomnoml draws the edge between the two declared boxes")
    func nomnomlGraph() throws {
        let source = "struct Outer { struct Inner {} }\nextension Outer.Inner {}"
        let graph = try NomnomlGraph(parsing: ClassDiagramIds.script(for: source, format: .nomnoml))
        #expect(graph.nodes.map(\.id) == ["Outer", "Outer.Inner", "Outer.Inner0"])
        #expect(graph.edges.map { [$0.start, $0.type, $0.end] }.contains(["Outer.Inner0", "-->", "Outer.Inner"]))
    }
}
