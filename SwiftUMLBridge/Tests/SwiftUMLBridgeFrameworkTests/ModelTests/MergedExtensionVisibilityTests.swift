import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Under `showExtensions: .merged`, an extension merges into the type its name means where it is
/// written, by the lookup SVG edges use (#74): only a type Swift's access control lets it see.
/// Merging ranked every same-named type, so an extension could merge into a `private` type in
/// another file, a box other than the one its nested type hangs off when extensions are drawn
/// apart (#107), or into a hidden `fileprivate` one, which took its members out of the diagram.
@Suite("Merged extensions — only a visible type is a merge target")
struct MergedExtensionVisibilityTests {

    /// A hand-built declaration in `file`, in `module`.
    private func declared(
        _ kind: ElementKind, _ name: String, in file: String, module: String,
        access: ElementAccessibility? = nil, members: [SyntaxStructure] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(
            accessibility: access, kind: kind, name: name, substructure: members.isEmpty ? nil : members
        )
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    private func member(_ name: String) -> SyntaxStructure {
        SyntaxStructure(kind: .varInstance, name: name, typename: "Int")
    }

    /// `<access> struct Foo { var hidden: Int }` in B.swift, beside the extension's file in ModM;
    /// `public struct Foo { var shown: Int }` in C.swift, in ModN; then
    /// `extension Foo { func bar() {}; struct Inner {} }` in A.swift, in ModM. From A.swift, only
    /// ModN's `Foo` is visible. `private` is drawn by default, `fileprivate` is not.
    private func shadowedFoo(_ access: ElementAccessibility = .private) -> [SyntaxStructure] {
        let bar = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let inner = declared(.struct, "Inner", in: "A.swift", module: "ModM")
        return [
            declared(.struct, "Foo", in: "B.swift", module: "ModM", access: access, members: [member("hidden")]),
            declared(.struct, "Foo", in: "C.swift", module: "ModN", access: .public, members: [member("shown")]),
            declared(.extension, "Foo", in: "A.swift", module: "ModM", members: [bar, inner])
        ]
    }

    private func graph(_ items: [SyntaxStructure], _ mode: ExtensionVisualization) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: items,
            configuration: Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        )
    }

    @Test("an extension merges into the type it can see, not a private one in another file")
    func mergesIntoVisibleType() {
        let laid = graph(shadowedFoo(), .merged)
        #expect(laid.nodeIds == ["Foo", "Foo_1", "Foo.Inner"])
        #expect(laid.memberLines == [["~ hidden: Int"], ["~ shown: Int", "~ bar()"], []])
        #expect(laid.edgeEnds == ["Foo_1 -> Foo.Inner"])
    }

    @Test("the merged box is the one the nested type hangs off when extensions are drawn apart")
    func mergedAndSeparateAgree() {
        #expect(graph(shadowedFoo(), .all).edgeEnds == ["Foo_1 -> Foo.Inner"])
        #expect(graph(shadowedFoo(), .merged).edgeEnds == ["Foo_1 -> Foo.Inner"])
    }

    @Test("a merged member never goes into a hidden type the extension cannot see")
    func mergedMemberStaysVisible() {
        let laid = graph(shadowedFoo(.fileprivate), .merged)
        #expect(laid.nodeIds == ["Foo", "Foo.Inner"])
        #expect(laid.memberLines == [["~ shown: Int", "~ bar()"], []])
        #expect(laid.edgeEnds == ["Foo -> Foo.Inner"])
    }

    @Test("PlantUML lists the merged member on the visible type and nests the type under it")
    func plantUMLUsesVisibleType() {
        let configuration = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        let script = DiagramScript(items: shadowedFoo(), configuration: configuration).text
        #expect(ClassDiagramIds.lines(of: script, containing: "bar").count == 1)
        #expect(ClassDiagramIds.lines(of: script, containing: "+--") == ["Foo0 +-- Foo.Inner"])
        let foo0 = script.components(separatedBy: "as Foo0").last ?? ""
        #expect(foo0.prefix(while: { $0 != "}" }).contains("bar"), "\(script)")
    }

    /// With no type visible, the extension extends a type outside the diagram, as the SVG
    /// lookup's fallback reads it, so it keeps its own box.
    @Test("an extension that can see no same-named type keeps its own box")
    func invisibleTypeIsNoTarget() {
        let bar = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let laid = graph([
            declared(.struct, "Foo", in: "B.swift", module: "ModM", access: .private, members: [member("hidden")]),
            declared(.extension, "Foo", in: "A.swift", module: "ModM", members: [bar])
        ], .merged)
        #expect(laid.nodeIds == ["Foo", "Foo_1"])
        #expect(laid.memberLines == [["~ hidden: Int"], ["~ bar()"]])
    }

    /// `internal` types of other modules: from ModC the extension extends a type outside the
    /// diagram, as the SVG lookup reads it when extensions are drawn apart.
    @Test("an internal type of another module is no merge target")
    func otherModulesInternalTypeIsNoTarget() {
        let bar = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let items = [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", members: [member("count")]),
            declared(.extension, "Foo", in: "C.swift", module: "ModC", members: [bar])
        ]
        #expect(graph(items, .merged).memberLines == [["~ count: Int"], ["~ bar()"]])
        #expect(graph(items, .all).memberLines == [["~ count: Int"], ["~ bar()"]])
    }

    /// `public extension Foo { struct Inner {} }` makes Inner public, so ModB can extend it. The
    /// lookup is built before any merge, from the declarations as written, so merging the public
    /// extension into `Foo` first cannot hide Inner from ModB.
    @Test("an extension of a type nested in a public extension merges into it from another module")
    func extensionOfTypeNestedInPublicExtension() {
        let method = SyntaxStructure(kind: .functionMethodInstance, name: "y")
        let inner = declared(.struct, "Inner", in: "A.swift", module: "ModA")
        let items = [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", access: .public),
            declared(.extension, "Foo", in: "A.swift", module: "ModA", access: .public, members: [inner]),
            declared(.extension, "Foo.Inner", in: "B.swift", module: "ModB", members: [method])
        ]
        let laid = graph(items, .merged)
        #expect(laid.nodeIds == ["Foo", "Foo.Inner"])
        #expect(laid.memberLines == [[], ["~ y()"]])
        #expect(laid.edgeEnds == ["Foo -> Foo.Inner"])
    }

    @Test("extensions of a type no extension can see share the first one's box")
    func outsideTypeExtensionsShareTheFirstBox() {
        let one = SyntaxStructure(kind: .functionMethodInstance, name: "one")
        let two = SyntaxStructure(kind: .functionMethodInstance, name: "two")
        let laid = graph([
            declared(.struct, "Foo", in: "B.swift", module: "ModM", access: .private, members: [member("hidden")]),
            declared(.extension, "Foo", in: "A.swift", module: "ModM", members: [one]),
            declared(.extension, "Foo", in: "C.swift", module: "ModM", members: [two])
        ], .merged)
        #expect(laid.nodeIds == ["Foo", "Foo_1"])
        #expect(laid.memberLines == [["~ hidden: Int"], ["~ one()", "~ two()"]])
    }
}
