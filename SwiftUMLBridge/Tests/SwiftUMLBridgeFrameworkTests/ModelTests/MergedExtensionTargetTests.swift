import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Under `showExtensions: .merged`, an extension's members go into the type of its name that
/// `LayoutGraphBuilder` resolves the name to: declared in the same file, then in the same module,
/// then the first. A type nested in the extension hangs off that same box, in every format.
/// Merging used to take the first same-named type while the nested type's SVG edge took the
/// nearest, so the two could land on different boxes (#107).
@Suite("Merged extensions — which same-named type they merge into")
struct MergedExtensionTargetTests {

    private static let merged = ElementOptions(showExtensions: .merged)

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

    /// `struct Foo { var count: Int }` in A.swift (ModA) and `struct Foo { var other: Int }` in
    /// B.swift (ModB), both at `access`, then `extension Foo { func bar() {}; struct Inner {} }`
    /// in `file`.
    private func twoFoos(
        extensionIn file: String, module: String?, access: ElementAccessibility? = nil
    ) -> [SyntaxStructure] {
        let count = SyntaxStructure(kind: .varInstance, name: "count", typename: "Int")
        let other = SyntaxStructure(kind: .varInstance, name: "other", typename: "Int")
        let bar = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let inner = declared(.struct, "Inner", in: file, module: module)
        return [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", access: access, members: [count]),
            declared(.struct, "Foo", in: "B.swift", module: "ModB", access: access, members: [other]),
            declared(.extension, "Foo", in: file, module: module, members: [bar, inner])
        ]
    }

    private func graph(_ items: [SyntaxStructure]) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: items, configuration: Configuration(elements: Self.merged, format: .svg)
        )
    }

    private func text(_ items: [SyntaxStructure], _ format: DiagramFormat) -> String {
        DiagramScript(items: items, configuration: Configuration(elements: Self.merged, format: format)).text
    }

    /// Each declared class's member lines, keyed by its id: from PlantUML's `class "<name>" as <id> … {`
    /// or Mermaid's `class <id>["<label>"] {` to the closing `}`, without stereotype lines.
    private func members(in script: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var current: String?
        for line in script.split(separator: "\n").map(String.init) {
            if line.hasPrefix("class ") {
                current = ClassDiagramIds.plantUML(in: line).first ?? ClassDiagramIds.mermaid(in: line).first
                if let current { result[current] = [] }
                continue
            }
            guard let id = current else { continue }
            let member = line.trimmingCharacters(in: .whitespaces)
            if member == "}" {
                current = nil
            } else if !member.hasPrefix("<<") {
                result[id, default: []].append(member)
            }
        }
        return result
    }

    // MARK: - Which Type an Extension Merges Into

    @Test("an extension merges into the same-named type in its own file")
    func mergesIntoSameFileType() {
        let laid = graph(twoFoos(extensionIn: "B.swift", module: "ModB"))
        #expect(laid.nodeIds == ["Foo", "Foo_1", "Foo.Inner"])
        #expect(laid.memberLines == [["~ count: Int"], ["~ other: Int", "~ bar()"], []])
        #expect(laid.edgeEnds == ["Foo_1 -> Foo.Inner"])
    }

    @Test("with no same-file type, it merges into the same-named type in its module")
    func mergesIntoSameModuleType() {
        let laid = graph(twoFoos(extensionIn: "B+Bar.swift", module: "ModB"))
        #expect(laid.memberLines == [["~ count: Int"], ["~ other: Int", "~ bar()"], []])
        #expect(laid.edgeEnds == ["Foo_1 -> Foo.Inner"])
    }

    /// Another module's type is visible only from `package` up (#116), so both are `public` here.
    @Test("with no same-file or same-module type, it merges into the first")
    func mergesIntoFirstType() {
        let laid = graph(twoFoos(extensionIn: "C.swift", module: "ModC", access: .public))
        #expect(laid.memberLines == [["~ count: Int", "~ bar()"], ["~ other: Int"], []])
        #expect(laid.edgeEnds == ["Foo -> Foo.Inner"])
    }

    /// `--package` lists files in hash order (#70), so the first `Foo` changes from run to run.
    @Test("which type an extension merges into does not depend on which file is listed first")
    func targetIgnoresListOrder() {
        let items = twoFoos(extensionIn: "B.swift", module: "ModB")
        let laid = graph([items[1], items[0], items[2]])
        #expect(laid.memberLines == [["~ other: Int", "~ bar()"], ["~ count: Int"], []])
        #expect(laid.edgeEnds == ["Foo -> Foo.Inner"])
    }

    @Test("a type the sources only extend keeps one box, its first extension's")
    func onlyExtendedTypeKeepsFirstExtension() {
        let one = SyntaxStructure(kind: .functionMethodInstance, name: "one")
        let two = SyntaxStructure(kind: .functionMethodInstance, name: "two")
        let laid = graph([
            declared(.extension, "String", in: "A.swift", members: [one]),
            declared(.extension, "String", in: "B.swift", members: [two, declared(.struct, "Inner", in: "B.swift")])
        ])
        #expect(laid.nodeIds == ["String.Inner", "String"])
        #expect(laid.memberLines == [[], ["~ one()", "~ two()"]])
        #expect(laid.edgeEnds == ["String -> String.Inner"])
    }

    // MARK: - Every Format Agrees

    @Test("PlantUML lists the merged member on the extension file's type and nests the type under it")
    func plantUMLUsesSameFileType() {
        let script = text(twoFoos(extensionIn: "B.swift", module: "ModB"), .plantuml)
        let byId = members(in: script)
        #expect(byId["Foo"] == ["~count : Int"])
        #expect(byId["Foo0"] == ["~other : Int", "~bar <&bolt>"])
        #expect(ClassDiagramIds.lines(of: script, containing: "+--") == ["Foo0 +-- Foo.Inner"])
    }

    @Test("Mermaid lists the merged member on the extension file's type")
    func mermaidUsesSameFileType() {
        let byId = members(in: text(twoFoos(extensionIn: "B.swift", module: "ModB"), .mermaid))
        #expect(byId["Foo"] == ["~Int count"])
        #expect(byId["Foo0"] == ["~Int other", "~bar()"])
    }

    /// Nomnoml names a node by its header, not its id (#69), so the two `Foo` boxes are told apart
    /// here by their members. The nested type's edge names the id PlantUML gives the same box.
    @Test("Nomnoml lists the merged member on the extension file's type")
    func nomnomlUsesSameFileType() {
        let script = text(twoFoos(extensionIn: "B.swift", module: "ModB"), .nomnoml)
        let withBar = ClassDiagramIds.lines(of: script, containing: "bar()")
        #expect(withBar == ["[<struct> Foo <<ModB>>|~other: Int|~bar()]"])
        #expect(ClassDiagramIds.lines(of: script, containing: "+-") == ["[Foo0] +- [Foo.Inner]"])
    }

    // MARK: - Nested Types

    @Test("a type nested in a merged extension of a nested type keeps its qualified name")
    func nestedTargetKeepsQualifiedNames() {
        let extended = SyntaxStructure.create(from: "struct A { struct B {} }\nextension A.B { struct Inner {} }")
        let nested = SyntaxStructure.create(from: "struct A { struct B { struct Inner {} } }")
        let extendedItems = extended?.substructure ?? []
        let nestedItems = nested?.substructure ?? []
        #expect(graph(extendedItems).nodeIds == ["A", "A.B", "A.B.Inner"])
        #expect(graph(extendedItems).edgeEnds == graph(nestedItems).edgeEnds)
        let plantUML = ClassDiagramIds.lines(of: text(extendedItems, .plantuml), containing: "+--")
        #expect(plantUML == ["A +-- A.B", "A.B +-- A.B.Inner"])
    }
}
