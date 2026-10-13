import Testing
@testable import SwiftUMLBridgeFramework

/// When several drawn types share a name, an edge that names it ends at the one Swift would
/// most likely mean: declared in the same file, then in the same module, then the first (#55).
@Suite("LayoutGraphBuilder — which same-named type an edge means")
struct LayoutGraphBuilderEdgeScopeTests {

    private func declared(
        _ kind: ElementKind,
        _ name: String,
        in file: String,
        module: String? = nil,
        inheriting inheritedTypes: [String] = [],
        nesting nested: [SyntaxStructure] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(
            inheritedTypes: inheritedTypes.isEmpty ? nil : inheritedTypes.map { SyntaxStructure(name: $0) },
            kind: kind,
            name: name,
            substructure: nested.isEmpty ? nil : nested
        )
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    private func edges(for items: [SyntaxStructure]) -> [String] {
        LayoutGraphBuilder.buildClassDiagram(from: items, configuration: .default)
            .edges.map { "\($0.sourceId) -> \($0.targetId)" }
    }

    @Test("a type nested in an extension hangs off the same-named type in the extension's file")
    func extensionNestedTypeUsesSameFileType() {
        let items = [
            declared(.struct, "Math", in: "Tests/Private.swift"),
            declared(.struct, "Math", in: "Math.swift"),
            declared(.extension, "Math", in: "Math.swift", nesting: [SyntaxStructure(kind: .struct, name: "Add")])
        ]
        #expect(edges(for: items) == ["Math_1 -> Math.Add"])
    }

    @Test("an inheritance edge ends at the same-named type in the subclass's file")
    func inheritanceUsesSameFileType() {
        let items = [
            declared(.protocol, "Simple", in: "A.swift"),
            declared(.protocol, "Simple", in: "B.swift"),
            declared(.struct, "Conformer", in: "B.swift", inheriting: ["Simple"])
        ]
        #expect(edges(for: items) == ["Conformer -> Simple_1"])
    }

    @Test("with no same-file type, the same-named type in the same module wins")
    func extensionNestedTypeUsesSameModuleType() {
        let items = [
            declared(.struct, "Name", in: "Tool/Name.swift", module: "Tool"),
            declared(.struct, "Name", in: "Core/Name.swift", module: "Core"),
            declared(.extension, "Name", in: "Core/Name+Case.swift", module: "Core",
                     nesting: [SyntaxStructure(kind: .enum, name: "Case")])
        ]
        #expect(edges(for: items) == ["Name_1 -> Name.Case"])
    }

    @Test("with no same-file or same-module type, the first declaration is used")
    func fallsBackToFirstDeclaration() {
        let items = [
            declared(.class, "Base", in: "A.swift"),
            declared(.class, "Base", in: "B.swift"),
            declared(.class, "Sub", in: "C.swift", inheriting: ["Base"])
        ]
        #expect(edges(for: items) == ["Sub -> Base"])
    }

    @Test("a same-file extension does not stand in for a type declared elsewhere")
    func sameFileExtensionDoesNotBeatTheType() {
        let items = [
            declared(.class, "Base", in: "Base.swift"),
            declared(.extension, "Base", in: "Sub.swift"),
            declared(.class, "Sub", in: "Sub.swift", inheriting: ["Base"])
        ]
        #expect(edges(for: items) == ["Sub -> Base"])
    }

    @Test("a same-file type beats an earlier type in the same module")
    func sameFileBeatsEarlierSameModuleType() {
        let items = [
            declared(.class, "Base", in: "Core/A.swift", module: "Core"),
            declared(.class, "Base", in: "Core/B.swift", module: "Core"),
            declared(.class, "Sub", in: "Core/B.swift", module: "Core", inheriting: ["Base"])
        ]
        #expect(edges(for: items) == ["Sub -> Base_1"])
    }

    @Test("within the same module, the first type is used")
    func firstOfTwoSameModuleTypes() {
        let items = [
            declared(.struct, "Name", in: "Tool/Name.swift", module: "Tool"),
            declared(.struct, "Name", in: "Core/A.swift", module: "Core"),
            declared(.struct, "Name", in: "Core/B.swift", module: "Core"),
            declared(.struct, "User", in: "Core/User.swift", module: "Core", inheriting: ["Name"])
        ]
        #expect(edges(for: items) == ["User -> Name_1"])
    }

    @Test("within the same file, the first type is used")
    func firstOfTwoSameFileTypes() {
        let source = "#if DEBUG\nclass Base {}\n#else\nclass Base {}\n#endif\nclass Sub: Base {}"
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: SyntaxStructure.create(from: source)?.substructure ?? [], configuration: .default
        )
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" } == ["Sub -> Base"])
    }

    @Test("two files with the same name in different folders are different files")
    func sameBasenameIsNotSameFile() {
        let items = [
            declared(.class, "Base", in: "App/Base.swift"),
            declared(.class, "Base", in: "Tests/Base.swift"),
            declared(.class, "Sub", in: "Tests/Base.swift", inheriting: ["Base"])
        ]
        #expect(edges(for: items) == ["Sub -> Base_1"])
    }

    @Test("a supertype the diagram declares only as extensions resolves to the first one")
    func extensionOnlySupertypeUsesFirstExtension() {
        let items = [
            declared(.extension, "Bar", in: "X.swift"),
            declared(.extension, "Bar", in: "Y.swift"),
            declared(.struct, "Foo", in: "Y.swift", inheriting: ["Bar"])
        ]
        #expect(edges(for: items) == ["Foo -> Bar"])
    }

    // MARK: - A nested type's own parent

    @Test("every type kind keeps its own nested types", arguments: ["class", "enum", "actor", "struct"])
    func everyKindKeepsItsOwnNestedTypes(keyword: String) {
        let source = "\(keyword) Fixture { struct Row {} }\n\(keyword) Fixture { struct Kind {} }"
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: SyntaxStructure.create(from: source)?.substructure ?? [], configuration: .default
        )
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" }
            == ["Fixture -> Fixture.Row", "Fixture_1 -> Fixture.Kind"])
    }

    @Test("the second of two same-named nested types keeps its own nested types")
    func sameNamedNestedTypesKeepTheirOwnChildren() {
        let source = """
            struct Outer {
            #if DEBUG
                struct Mid { struct A {} }
            #else
                struct Mid { struct B {} }
            #endif
            }
            """
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: SyntaxStructure.create(from: source)?.substructure ?? [], configuration: .default
        )
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" } == [
            "Outer -> Outer.Mid", "Outer.Mid -> Outer.Mid.A",
            "Outer -> Outer.Mid_1", "Outer.Mid_1 -> Outer.Mid.B"
        ])
    }

    @Test("a parent that is not drawn falls back to the type its qualified name means")
    func undrawnParentFallsBackToItsName() {
        // Only reachable by hand: parsed nested types always have their parent drawn.
        let outer = SyntaxStructure(kind: .struct, name: "Outer")
        let drawnMid = SyntaxStructure(kind: .struct, name: "Mid")
        drawnMid.parent = outer
        let staleMid = SyntaxStructure(kind: .struct, name: "Mid")
        staleMid.parent = outer
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        inner.parent = staleMid
        let graph = LayoutGraphBuilder.buildClassDiagram(
            from: [outer, SyntaxStructure(kind: .struct, name: "Mid"), drawnMid, inner],
            configuration: Configuration(elements: ElementOptions(showNestedTypes: false), format: .svg)
        )
        #expect(graph.edges.map { "\($0.sourceId) -> \($0.targetId)" }
            == ["Outer -> Outer.Mid", "Outer.Mid -> Outer.Mid.Inner"])
    }

    @Test("an extension stands in for a type the diagram does not declare")
    func extensionStandsInForUndeclaredType() {
        let items = [
            declared(.extension, "String", in: "A.swift", nesting: [SyntaxStructure(kind: .struct, name: "Inner")])
        ]
        #expect(edges(for: items) == ["String -> String.Inner"])
    }

    @Test("with no such type drawn, a type nested in an extension hangs off that very extension")
    func undeclaredTypeNestsInItsOwnExtension() {
        let items = [
            declared(.extension, "String", in: "A.swift", nesting: [SyntaxStructure(kind: .struct, name: "A")]),
            declared(.extension, "String", in: "B.swift", nesting: [SyntaxStructure(kind: .struct, name: "B")])
        ]
        #expect(edges(for: items) == ["String -> String.A", "String_1 -> String.B"])
    }
}
