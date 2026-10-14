import Testing
@testable import SwiftUMLBridgeFramework

/// When a class diagram does not draw a nested type's parent, PlantUML and Nomnoml end its edge
/// where SVG does (`LayoutGraphBuilder.EdgeEndIds`): on a drawn extension that stands in for the
/// hidden type, on the type a hidden extension extends, or else on the parent's qualified name,
/// which they draw as a node of its own (#67). That name used to be written even when a drawn,
/// unrelated element already had it as its id, so the nested type hung off that element.
@Suite("Nested-type edges to a parent the diagram does not draw")
struct NestedEdgeStandInTests {

    /// A hand-built declaration in `file`, in `module`.
    private func declared(
        _ kind: ElementKind, _ name: String, in file: String, module: String? = nil,
        access: ElementAccessibility? = nil, members: [SyntaxStructure] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(
            accessibility: access, kind: kind, name: name, substructure: members.isEmpty ? nil : members
        )
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    /// `fileprivate struct Foo { struct Inner {} }` in A.swift; `fileprivate` is hidden by default.
    private func hiddenFoo() -> SyntaxStructure {
        declared(.struct, "Foo", in: "A.swift", access: .fileprivate,
                 members: [declared(.struct, "Inner", in: "A.swift")])
    }

    /// `extension Foo { func bar() {} }` in `file`.
    private func fooExtension(in file: String) -> SyntaxStructure {
        declared(.extension, "Foo", in: file, members: [SyntaxStructure(kind: .functionMethodInstance, name: "bar")])
    }

    private func edges(
        _ items: [SyntaxStructure], _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all
    ) -> [String] {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        let script = DiagramScript(items: items, configuration: configuration)
        if format == .svg { return script.layoutGraph?.edgeEnds ?? [] }
        return ClassDiagramIds.lines(of: script.text, containing: format == .plantuml ? "+--" : "+-")
    }

    // MARK: - A Hidden Type Parent

    /// B.swift cannot see A's `fileprivate` `Foo`, so its extension extends some other `Foo`.
    @Test("a hidden type's nested type does not hang off an extension of another type of its name",
          arguments: [ExtensionVisualization.all, .merged])
    func unrelatedExtensionIsNoStandIn(extensions: ExtensionVisualization) {
        let items = [hiddenFoo(), fooExtension(in: "B.swift")]
        #expect(edges(items, .plantuml, extensions).isEmpty)
        #expect(edges(items, .nomnoml, extensions).isEmpty)
        #expect(edges(items, .svg, extensions).isEmpty)
    }

    @Test("with the extension hidden, the hidden type is named by its qualified name again")
    func hiddenExtensionLeavesTheNameFree() {
        let items = [hiddenFoo(), fooExtension(in: "B.swift")]
        #expect(edges(items, .plantuml, .none) == ["Foo +-- Foo.Inner"])
        #expect(edges(items, .nomnoml, .none) == ["[Foo] +- [Foo.Inner]"])
    }

    @Test("an extension in the hidden type's own file stands in for it, as in SVG")
    func sameFileExtensionStandsIn() {
        let items = [hiddenFoo(), fooExtension(in: "A.swift")]
        #expect(edges(items, .plantuml) == ["Foo +-- Foo.Inner"])
        #expect(edges(items, .svg) == ["Foo -> Foo.Inner"])
    }

    /// B's extension takes the id `Foo` as the first declaration of the name; A's is `Foo0`.
    @Test("the stand-in is the extension that sees the hidden type, not the first of its name")
    func standInIsNotTheFirstOfItsName() {
        let items = [hiddenFoo(), fooExtension(in: "B.swift"), fooExtension(in: "A.swift")]
        #expect(edges(items, .plantuml) == ["Foo0 +-- Foo.Inner"])
        #expect(edges(items, .svg) == ["Foo_1 -> Foo.Inner"])
    }

    @Test("a hidden type's nested type does not hang off a drawn type of its name")
    func unrelatedTypeIsNoParent() {
        let items = [hiddenFoo(), declared(.struct, "Foo", in: "B.swift", access: .private)]
        #expect(edges(items, .plantuml).isEmpty)
        #expect(edges(items, .nomnoml).isEmpty)
        #expect(edges(items, .svg).isEmpty)
    }

    // MARK: - A Hidden Extension Parent

    /// With extensions hidden, a type nested in one hangs off the type the extension extends as
    /// seen from the extension's file, not the first type of that name.
    @Test("a type nested in a hidden extension hangs off the type that extension extends")
    func hiddenExtensionParentFindsItsType() {
        let items = [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", access: .public),
            declared(.struct, "Foo", in: "B.swift", module: "ModB", access: .public),
            declared(.extension, "Foo", in: "B.swift", module: "ModB",
                     members: [declared(.struct, "Inner", in: "B.swift", module: "ModB")])
        ]
        #expect(edges(items, .plantuml, .none) == ["Foo0 +-- Foo.Inner"])
        #expect(edges(items, .nomnoml, .none) == ["[Foo0] +- [Foo.Inner]"])
        #expect(edges(items, .svg, .none) == ["Foo_1 -> Foo.Inner"])
    }
}
