import Testing
@testable import SwiftUMLBridgeFramework

/// `[Int]`, `[String: Int]` and `Int?` always mean Swift's `Array`, `Dictionary` and `Optional`,
/// even where the project declares a type of that name. `extendedTypeName` names such an
/// extension `Array`, `Dictionary` or `Optional` (#66), and `TypeLookup` then found the project's
/// type: `--merge-extensions` merged the members into it, and the `ext` edge and the edges of the
/// types nested in the extension ended on it (#126).
@Suite("Sugared extensions extend the standard library's type, not a project's own")
struct SugaredExtensionTargetTests {
    /// Compiles (`swiftc -typecheck`): the project's types shadow the names, not the sugar.
    private static let shadowing = """
        struct Array {}
        struct Optional {}
        struct Dictionary {}
        struct InlineArray {}
        extension [Int] { var total: Int { reduce(0, +) } }
        extension Int? { var orZero: Int { self ?? 0 } }
        extension [String: Int] { var keyCount: Int { count } }
        extension [3 of Int] { var size: Int { count } }
        """

    private func script(
        _ source: String, _ format: DiagramFormat, _ mode: ExtensionVisualization = .all
    ) -> String {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    private func extEdges(_ source: String, _ format: DiagramFormat) -> [String] {
        let marker = format == .nomnoml ? "] --> " : " <.. "
        return ClassDiagramIds.lines(of: script(source, format), containing: marker)
    }

    /// Member lines `--merge-extensions` marks as merged into a type (`<&bolt>`).
    private func mergedMembers(_ source: String) -> [String] {
        script(source, .plantuml, .merged).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasSuffix("<&bolt>") }
    }

    private func mergedIds(_ source: String) -> [String] {
        ClassDiagramIds.plantUML(in: script(source, .plantuml, .merged))
    }

    private func graph(_ source: String, _ mode: ExtensionVisualization = .all) -> LayoutGraph? {
        let configuration = Configuration(elements: ElementOptions(showExtensions: mode), format: .svg)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
    }

    /// The items `source` parses to, each stamped as declared in `file`, so two in-memory sources
    /// are two files, as they are on disk.
    private func parsed(_ source: String, file: String) throws -> [SyntaxStructure] {
        let items = try #require(SyntaxStructure.create(from: source)?.substructure)
        func stamp(_ item: SyntaxStructure) {
            item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
            item.substructure?.forEach(stamp)
        }
        items.forEach(stamp)
        return items
    }

    // MARK: - Parsing

    @Test("the parser marks an extension or typealias written with sugar, and no other")
    func parserMarksSugar() throws {
        let items = try #require(SyntaxStructure.create(from: """
            extension [Int] {}
            extension Int? {}
            extension [Int].Index {}
            extension Array {}
            extension Swift.Array<Int> {}
            typealias Numbers = [Int]
            typealias Plain = Array<Int>
            """)?.substructure)
        #expect(items.map(\.isSugared) == [true, true, true, false, false, true, false])
    }

    // MARK: - The issue's witnesses

    @Test("--merge-extensions leaves a project's Array, Optional, Dictionary and InlineArray alone")
    func mergeLeavesLocalTypesAlone() {
        #expect(mergedMembers(Self.shadowing) == [])
        #expect(mergedIds(Self.shadowing) == [
            "Array", "Optional", "Dictionary", "InlineArray", "Array0", "Optional1", "Dictionary2", "InlineArray3"
        ])
    }

    @Test("a sugared extension draws no ext edge to a project's type",
          arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml])
    func noExtEdgeToLocalType(format: DiagramFormat) {
        #expect(extEdges(Self.shadowing, format) == [])
    }

    @Test("SVG hangs a type nested in a sugared extension off that extension", arguments: [
        ExtensionVisualization.all, .merged
    ])
    func svgNestedTypeEdge(mode: ExtensionVisualization) {
        let source = "struct Array {}\nextension [Int] { struct Summary {} }"
        #expect(graph(source, mode)?.edgeEnds == ["Array_1 -> Array.Summary"])
    }

    @Test("PlantUML and Nomnoml hang a type nested in a sugared extension off that extension", arguments: [
        ExtensionVisualization.all, .merged
    ])
    func textNestedTypeEdge(mode: ExtensionVisualization) {
        let source = "struct Array {}\nextension [Int] { struct Summary {} }"
        #expect(ClassDiagramIds.lines(of: script(source, .plantuml, mode), containing: "+--")
            == ["Array0 +-- Array.Summary"])
        #expect(ClassDiagramIds.lines(of: script(source, .nomnoml, mode), containing: "+-")
            == ["[Array0] +- [Array.Summary]"])
    }

    @Test("--hide-extensions gives a type nested in a sugared extension no edge to a project's type")
    func hiddenSugaredExtensionNestedType() {
        let source = "struct Array {}\nextension [Int] { struct Summary {} }"
        #expect(graph(source, .none)?.edgeEnds == [])
        #expect(ClassDiagramIds.lines(of: script(source, .plantuml, .none), containing: "+--") == [])
        #expect(ClassDiagramIds.lines(of: script(source, .nomnoml, .none), containing: "+-") == [])
    }

    // MARK: - Other spellings of the sugar

    @Test("a typealias of a sugared type extends the standard library's type too")
    func aliasOfSugar() {
        let source = """
            struct Dictionary {}
            typealias JSON = [String: Int]
            extension JSON { var keyCount: Int { count } }
            """
        #expect(mergedMembers(source) == [])
        #expect(extEdges(source, .plantuml) == [])
    }

    /// `Outer.Numbers` and `[Int]` both extend Swift's `Array`, so they share the first one's box,
    /// though `Array` written inside `Outer` would mean `Outer.Array`.
    @Test("an alias of a sugared type, declared in a type with a member of that name, is no alias of the member")
    func memberAliasOfSugar() {
        let source = """
            enum Outer {
                struct Array {}
                typealias Numbers = [Int]
            }
            extension Outer.Numbers { var total: Int { reduce(0, +) } }
            extension [Int] { var doubled: [Int] { map { $0 * 2 } } }
            """
        #expect(mergedMembers(source) == [])
        #expect(extEdges(source, .plantuml) == [])
        #expect(mergedIds(source) == ["Outer", "Outer.Array", "Outer.Numbers"])
    }

    // MARK: - Members past the sugar

    @Test("a member of a sugared type is not the project's type of that path")
    func memberOfSugar() {
        let source = """
            struct Array { struct Index {} }
            extension [Int].Index { var next: Int { 0 } }
            """
        #expect(mergedMembers(source) == [])
        #expect(extEdges(source, .plantuml) == [])
    }

    /// Only the base of `[Int].Stats` is Swift's type. `Stats` is the project's, declared in an
    /// extension of Swift's `Array`, so `extension [Int].Stats` extends it.
    @Test("a member the project declares in a sugared extension is the one a sugared path names", arguments: [
        (DiagramFormat.plantuml, "Array.Stats <.. Array.Stats0 : ext"),
        (.mermaid, "Array.Stats <.. Array.Stats0 : ext"),
        (.nomnoml, "[Array.Stats0] --> ext [Array.Stats]")
    ])
    func memberDeclaredInSugaredExtension(format: DiagramFormat, edge: String) {
        let source = """
            extension [Int] { struct Stats { var count = 0 } }
            extension [Int].Stats { var isEmpty: Bool { count == 0 } }
            """
        #expect(extEdges(source, format) == [edge])
        #expect(mergedMembers(source) == ["~isEmpty : Bool <&bolt>"])
    }

    @Test("with no project Array, a member declared in a bare extension is the one a sugared path names")
    func memberDeclaredInBareExtension() {
        let direct = "extension Array { struct Item {} }\nextension [Int].Item { var next: Int { 0 } }"
        #expect(extEdges(direct, .plantuml) == ["Array.Item <.. Array.Item0 : ext"])
        let aliased = "extension Array { struct Item {} }\ntypealias IntItem = [Int].Item\nextension IntItem {}"
        #expect(extEdges(aliased, .plantuml) == ["Array.Item <.. IntItem : ext"])
    }

    /// A project `struct Array` with its own `Stats` does not change what `[Int].Stats` names.
    @Test("beside a project Array's member of that name, a sugared path names the sugared extension's")
    func memberOfSugaredExtensionBesideLocalMember() {
        let source = """
            struct Array { struct Stats {} }
            extension [Int] { struct Stats { var count = 0 } }
            extension [Int].Stats { var isEmpty: Bool { count == 0 } }
            """
        #expect(extEdges(source, .plantuml) == ["Array.Stats0 <.. Array.Stats2 : ext"])
    }

    @Test("a sugared path through a member typealias means the type it aliases")
    func memberTypealiasInSugaredExtension() {
        let source = """
            struct Array {}
            struct Foo { var value = 0 }
            extension [Int] { typealias Alias = Foo }
            extension [Int].Alias { var doubled: Int { value * 2 } }
            """
        #expect(extEdges(source, .plantuml) == ["Foo <.. Array.Alias : ext"])
        #expect(mergedMembers(source) == ["~doubled : Int <&bolt>"])
    }

    /// `--hide-extensions` hangs `Bucket`, declared in `extension [Int].Stats`, off `Stats`.
    @Test("a type nested in an extension of a sugared path hangs off the member it extends")
    func nestedInExtensionOfSugaredPath() {
        let source = """
            extension [Int] { struct Stats {} }
            extension [Int].Stats { struct Bucket {} }
            """
        #expect(ClassDiagramIds.lines(of: script(source, .plantuml, .none), containing: "+--")
            .contains("Array.Stats +-- Array.Stats.Bucket"))
        #expect(graph(source, .none)?.edgeEnds.contains("Array.Stats -> Array.Stats.Bucket") == true)
    }

    // MARK: - Access and stand-ins

    /// A type nested in an extension is no more visible than the type the extension extends. For
    /// `extension [Int]` that is Swift's `Array`, not a `fileprivate` one in the same file, so
    /// another file still reaches the nested type.
    @Test("a type nested in a sugared extension is not capped by a project type's access")
    func nestedAccessIsNotCapped() throws {
        let items = try parsed(
            "fileprivate struct Array {}\nextension [Int] { class Summary {} }", file: "A.swift"
        ) + parsed("class Detailed: Array.Summary {}", file: "B.swift")
        let configuration = Configuration(format: .svg)
        let graph = DiagramScript(items: items, configuration: configuration).layoutGraph
        #expect(graph?.edgeEnds.contains("Detailed -> Array.Summary") == true)
    }

    /// The default access levels hide a `fileprivate` type, and its first drawn extension stands
    /// in for it (#153). A sugared extension does not extend it, so it is never that stand-in:
    /// the bare one is, and the two keep a box each.
    @Test("--merge-extensions never makes a sugared extension a hidden project type's stand-in")
    func neverStandsInForHiddenType() {
        let source = """
            fileprivate struct Array {}
            extension [Int] { func sugared() {} }
            extension Array { func bare() {} }
            """
        #expect(mergedIds(source) == ["Array", "Array0"])
        #expect(graph(source, .merged)?.nodeIds == ["Array", "Array_1"])
    }

    /// A type nested in a hidden type hangs off the type's first drawn extension, its edge-end
    /// stand-in. The sugared extension is not one, so `Inner` hangs off the bare extension, and
    /// with no bare one it gets no edge.
    @Test("a type nested in a hidden project type never hangs off a sugared extension")
    func nestedTypeOfHiddenTypeSkipsSugaredStandIn() {
        let withBare = """
            fileprivate struct Array { struct Inner {} }
            extension [Int] { var total: Int { 0 } }
            extension Array { var bare: Int { 0 } }
            """
        #expect(ClassDiagramIds.lines(of: script(withBare, .plantuml), containing: "+--")
            == ["Array0 +-- Array.Inner"])
        #expect(ClassDiagramIds.lines(of: script(withBare, .nomnoml), containing: "+-")
            == ["[Array0] +- [Array.Inner]"])
        #expect(graph(withBare)?.edgeEnds == ["Array_1 -> Array.Inner"])
        let sugaredOnly = "fileprivate struct Array { struct Inner {} }\nextension [Int] { var total: Int { 0 } }"
        #expect(ClassDiagramIds.lines(of: script(sugaredOnly, .plantuml), containing: "+--") == [])
        #expect(ClassDiagramIds.lines(of: script(sugaredOnly, .nomnoml), containing: "+-") == [])
        #expect(graph(sugaredOnly)?.edgeEnds == [])
    }

    // MARK: - Controls

    @Test("a bare Array still means the project's own")
    func bareMeansLocalType() {
        let bare = "struct Array {}\nextension Array { var local: Int { 0 } }"
        #expect(mergedMembers(bare) == ["~local : Int <&bolt>"])
        #expect(extEdges(bare, .plantuml) == ["Array <.. Array0 : ext"])
        #expect(graph("struct Array {}\nextension Array { struct Summary {} }")?.edgeEnds
            == ["Array -> Array.Summary"])
    }

    @Test("without a project type, a sugared extension gets no edge and nothing to merge into")
    func withoutLocalType() {
        let alone = "extension [Int] { var total: Int { 0 } }\nextension Int? { var orZero: Int { 0 } }"
        #expect(mergedMembers(alone) == [])
        #expect(extEdges(alone, .plantuml) == [])
    }

    @Test("without a project type, [Int] and a bare Array share one box (#66)")
    func withoutLocalTypeSugarAndBareShareABox() {
        let both = """
            extension [Int] { var total: Int { 0 } }
            extension Array where Element == String { var joinedCount: Int { 0 } }
            """
        #expect(mergedIds(both) == ["Array"])
    }

    /// `extension JSON` and `extension [String: Int]` both extend Swift's `Dictionary`, so they
    /// share the first one's box, `JSON`; a bare `extension Dictionary` merges into the project's.
    @Test("beside a project's own type, extensions of the standard library's still share one box")
    func sugaredExtensionsShareABox() {
        let source = """
            struct Array {}
            struct Dictionary {}
            extension [Int] { var total: Int { 0 } }
            extension [String] { var joined: String { "" } }
            typealias JSON = [String: Int]
            extension JSON { var keyCount: Int { 0 } }
            extension [String: Int] { var isBlank: Bool { true } }
            extension Dictionary { var local: Int { 0 } }
            """
        #expect(mergedIds(source) == ["Array", "Dictionary", "Array0", "JSON"])
        #expect(mergedMembers(source) == ["~local : Int <&bolt>"])
    }
}
