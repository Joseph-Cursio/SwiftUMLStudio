import Testing
@testable import SwiftUMLBridgeFramework

/// Class-diagram preparation edits the structures it works on, and it used to edit the caller's
/// parsed items: a second diagram from the same items saw the first one's merged members, parent
/// links and merge indicators (#73). It now works on a private copy, so these hold.
@Suite("Class-diagram preparation — repeatable and non-mutating")
struct ClassDiagramPreparationRepeatTests {

    private static let merged = ElementOptions(showExtensions: .merged)
    private static let mergedSVG = Configuration(elements: merged, format: .svg)

    private func items(_ source: String, module: String? = nil) -> [SyntaxStructure] {
        SyntaxStructure.create(from: source, module: module)?.substructure ?? []
    }

    private func graph(_ items: [SyntaxStructure], _ configuration: Configuration = mergedSVG) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(from: items, configuration: configuration)
    }

    private func text(
        _ items: [SyntaxStructure], _ format: DiagramFormat, elements: ElementOptions = merged
    ) -> String {
        DiagramScript(items: items, configuration: Configuration(elements: elements, format: format)).text
    }

    private func declared(
        _ kind: ElementKind, _ name: String, in file: String, module: String? = nil,
        members: [SyntaxStructure] = []
    ) -> SyntaxStructure {
        let item = SyntaxStructure(kind: kind, name: name, substructure: members.isEmpty ? nil : members)
        item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
        item.module = module
        return item
    }

    // MARK: - The Same Items, Prepared Again

    @Test("building the class-diagram graph twice from the same items gives the same members")
    func buildClassDiagramIsRepeatable() {
        let parsed = items("struct Foo { var count: Int }\nextension Foo { func bar() {} }")
        let first = graph(parsed)
        let second = graph(parsed)
        #expect(first.memberLines == [["~ count: Int", "~ bar()"]])
        #expect(second.memberLines == first.memberLines)
    }

    @Test("building twice keeps a type nested in a merged extension to one node")
    func nestedBuildIsRepeatable() {
        let parsed = items("struct Foo {}\nextension Foo { struct Inner {} }")
        for _ in 1...2 {
            let laid = graph(parsed)
            #expect(laid.nodeIds == ["Foo", "Foo.Inner"])
            #expect(laid.edgeEnds == ["Foo -> Foo.Inner"])
        }
    }

    @Test("an SVG script built twice from the same items is the same")
    func svgScriptIsRepeatable() {
        let parsed = items("struct Foo { var count: Int }\nextension Foo { func bar() {} struct Inner {} }")
        let first = DiagramScript(items: parsed, configuration: Self.mergedSVG)
        let second = DiagramScript(items: parsed, configuration: Self.mergedSVG)
        #expect(first.layoutGraph?.memberLines == [["~ count: Int", "~ bar()"], []])
        #expect(second.layoutGraph?.memberLines == first.layoutGraph?.memberLines)
        #expect(second.text == first.text)
    }

    @Test("a merged PlantUML script is the same the second time")
    func mergedPlantUMLIsRepeatable() {
        let parsed = items("struct Foo { var count: Int }\nextension Foo { func bar() {} }")
        let first = text(parsed, .plantuml)
        #expect(ClassDiagramIds.lines(of: first, containing: "~bar <&bolt>").count == 1)
        #expect(text(parsed, .plantuml) == first)
    }

    @Test("a merged diagram leaves no merge indicator on a later unmerged one")
    func mergedThenAllDoesNotLeakTheIndicator() {
        let source = "struct Foo { var count: Int }\nextension Foo { func bar() {} }"
        let parsed = items(source)
        _ = graph(parsed)
        _ = text(parsed, .plantuml)
        let all = ElementOptions(showExtensions: .all)
        let later = text(parsed, .plantuml, elements: all)
        #expect(later == text(items(source), .plantuml, elements: all))
        #expect(!later.contains("<&bolt>"))
        #expect(ClassDiagramIds.plantUML(in: later) == ["Foo", "Foo0"])
    }

    @Test("a later merged run without an indicator shows none")
    func indicatorIsNotStale() {
        let parsed = items("struct Foo {}\nextension Foo { func bar() {} }")
        _ = text(parsed, .plantuml)
        let bare = ElementOptions(showExtensions: .merged, mergedExtensionMemberIndicator: nil)
        #expect(!text(parsed, .plantuml, elements: bare).contains("<&bolt>"))
    }

    @Test("every format leaves the parsed items as they were")
    func preparationLeavesItemsUntouched() throws {
        let parsed = items("struct Foo { var count: Int }\nextension Foo { func bar() {} struct Inner {} }")
        let foo = try #require(parsed.first)
        let fooMembers = foo.substructure ?? []
        let extensionMembers = try #require(parsed.last?.substructure)
        for format in [DiagramFormat.plantuml, .mermaid, .nomnoml, .svg] {
            _ = text(parsed, format)
        }
        let keptMembers = (foo.substructure ?? []).count == fooMembers.count
            && zip(foo.substructure ?? [], fooMembers).allSatisfy { $0 === $1 }
        #expect(keptMembers)
        #expect(extensionMembers.allSatisfy { $0.memberSuffix == nil && $0.parent == nil })
    }

    /// Every structure reachable from `roots` through `substructure`, by identity.
    private func identities(under roots: [SyntaxStructure]) -> Set<ObjectIdentifier> {
        var seen: Set<ObjectIdentifier> = []
        var pending = roots
        while let next = pending.popLast() {
            guard seen.insert(ObjectIdentifier(next)).inserted else { continue }
            pending.append(contentsOf: next.substructure ?? [])
        }
        return seen
    }

    @Test("the prepared items and their members are copies, never the caller's")
    func preparedItemsAreCopies() {
        let parsed = items("struct Foo { struct Inner {} }\nextension Foo { func bar() {} }")
        let prepared = parsed.preparedForClassDiagram(with: Configuration(elements: Self.merged))
        #expect(prepared.map(\.fullName) == ["Foo", "Foo.Inner"])
        // Nested types and members too, not only the top-level items the caller holds.
        let shared = identities(under: parsed).intersection(identities(under: prepared))
        #expect(shared.isEmpty)
    }

    // MARK: - Parent Identity After Copying

    @Test("PlantUML nests merged nested types under their qualified parents, every time")
    func plantUMLDeepNestingUnderMerge() {
        let parsed = items(
            "struct A { struct B { struct C {} } }\nextension A.B { func m() {} }\nextension A.B.C { func n() {} }"
        )
        for _ in 1...2 {
            #expect(ClassDiagramIds.lines(of: text(parsed, .plantuml), containing: "+--")
                == ["A +-- A.B", "A.B +-- A.B.C"])
        }
    }

    /// Pins one build's output and checks a second build repeats it. The merged `bar()` lands on
    /// the `Foo` in the extension's file, the box `Foo.Inner` hangs off (`MergedExtensionTargetTests`).
    @Test("same-named types in two files give the same graph when built twice")
    func sameNamedTypesInTwoFiles() {
        let count = SyntaxStructure(kind: .varInstance, name: "count", typename: "Int")
        let other = SyntaxStructure(kind: .varInstance, name: "other", typename: "Int")
        let bar = SyntaxStructure(kind: .functionMethodInstance, name: "bar")
        let inner = declared(.struct, "Inner", in: "B.swift", module: "ModB")
        let parsed = [
            declared(.struct, "Foo", in: "A.swift", module: "ModA", members: [count]),
            declared(.struct, "Foo", in: "B.swift", module: "ModB", members: [other]),
            declared(.extension, "Foo", in: "B.swift", module: "ModB", members: [bar, inner])
        ]
        for _ in 1...2 {
            let laid = graph(parsed)
            #expect(laid.nodeIds == ["Foo", "Foo_1", "Foo.Inner"])
            #expect(laid.memberLines == [["~ count: Int"], ["~ other: Int", "~ bar()"], []])
            #expect(laid.nodes.map(\.module) == ["ModA", "ModB", "ModB"])
            #expect(laid.edgeEnds == ["Foo_1 -> Foo.Inner"])
        }
    }

    @Test("a hand-set parent still means that very declaration, not the first of its name")
    func handSetParentKeepsItsIdentity() {
        let first = declared(.struct, "Outer", in: "A.swift")
        let second = declared(.struct, "Outer", in: "A.swift")
        let child = declared(.struct, "Child", in: "A.swift")
        child.parent = second
        let elements = ElementOptions(showNestedTypes: false)
        let laid = graph([first, second, child], Configuration(elements: elements, format: .svg))
        #expect(laid.edgeEnds == ["Outer_1 -> Outer.Child"])
        let plantUML = text([first, second, child], .plantuml, elements: elements)
        #expect(ClassDiagramIds.lines(of: plantUML, containing: "+--") == ["Outer0 +-- Outer.Child"])
    }

    @Test("a caller's hand-set parent links survive preparation")
    func handSetParentsSurviveTheCopy() {
        // As in LayoutGraphBuilderEdgeScopeTests.undrawnParentFallsBackToItsName, plus an extension.
        let outer = SyntaxStructure(kind: .struct, name: "Outer")
        let drawnMid = SyntaxStructure(kind: .struct, name: "Mid")
        drawnMid.parent = outer
        let staleMid = SyntaxStructure(kind: .struct, name: "Mid")
        staleMid.parent = outer
        let inner = SyntaxStructure(kind: .struct, name: "Inner")
        inner.parent = staleMid
        let ext = SyntaxStructure(
            kind: .extension, name: "Outer.Mid",
            substructure: [SyntaxStructure(kind: .functionMethodInstance, name: "m")]
        )
        let parsed = [outer, SyntaxStructure(kind: .struct, name: "Mid"), drawnMid, inner, ext]
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        for _ in 1...2 {
            let laid = graph(parsed, Configuration(elements: elements, format: .svg))
            #expect(laid.nodeIds == ["Outer", "Mid", "Outer.Mid", "Outer.Mid.Inner"])
            #expect(laid.memberLines == [[], [], ["~ m()"], []])
            #expect(laid.edgeEnds == ["Outer -> Outer.Mid", "Outer.Mid -> Outer.Mid.Inner"])
        }
        let linksKept = inner.parent === staleMid && drawnMid.parent === outer && staleMid.parent === outer
        #expect(linksKept)
    }

    /// UI imports Networking, whose `Client` is public, as Swift needs to extend it: without the
    /// import, `extension Client` names no type its file sees, and the lookup takes it for one of
    /// a type outside the diagram.
    @Test("a merged type keeps its own module and source location")
    func mergedTypeKeepsItsScope() {
        let parsed = items("public struct Client {}", module: "Networking")
            + items("import Networking\nextension Client { func render() {} }", module: "UI")
        for _ in 1...2 {
            let laid = graph(parsed)
            #expect(laid.nodeIds == ["Client"])
            #expect(laid.nodes.map(\.module) == ["Networking"])
            #expect(laid.nodes.first?.sourceLocation?.line == 1)
            #expect(laid.memberLines == [["~ render()"]])
        }
    }
}
