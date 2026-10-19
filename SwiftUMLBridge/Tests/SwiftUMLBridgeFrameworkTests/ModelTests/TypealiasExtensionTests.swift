import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// After `typealias Alias = Real`, `extension Alias {}` extends `Real`: its members merge into
/// `Real`, its `ext` edge ends on `Real`, and a type nested in it hangs off `Real`. The parser
/// dropped every typealias, so `TypeLookup` treated the extension as one of a type outside the
/// diagram, or of an imported type that happened to share the alias's name (#125).
@Suite("Extensions written through a typealias")
struct TypealiasExtensionTests {
    private static let throughAliases = """
        struct Outer { struct Inner {} }
        typealias Inner = Outer.Inner
        extension Inner { func viaInnerAlias() {} }
        struct Real {}
        typealias Alias = Real
        extension Alias { func viaAlias() {} }
        """

    private func script(_ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization) -> String {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    private func declaredIds(_ text: String, _ format: DiagramFormat) -> [String] {
        format == .mermaid ? ClassDiagramIds.mermaid(in: text) : ClassDiagramIds.plantUML(in: text)
    }

    private func extEdges(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.contains("<..") }
    }

    /// The items `source` parses to, each stamped as declared in `file` of `module`, so two
    /// in-memory sources are two files, as they are on disk.
    private func parsed(_ source: String, file: String, module: String? = nil) throws -> [SyntaxStructure] {
        let items = try #require(SyntaxStructure.create(from: source, module: module)?.substructure)
        func stamp(_ item: SyntaxStructure) {
            item.sourceLocation = SourceLocation(filePath: file, line: 1, column: 1)
            item.substructure?.forEach(stamp)
        }
        items.forEach(stamp)
        return items
    }

    private func mergedIds(of items: [SyntaxStructure]) -> [String] {
        let merged = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        return ClassDiagramIds.plantUML(in: DiagramScript(items: items, configuration: merged).text)
    }

    // MARK: - Parsing

    @Test("the parser keeps a typealias, top level and nested, with the type it names")
    func parsesTypealiases() throws {
        let items = try #require(SyntaxStructure.create(from: """
            typealias Alias = Real
            public typealias IntBox = Box<Int>
            typealias JSON = [String: Int]
            struct Container { private typealias Element = Outer.Inner }
            """)?.substructure)
        let aliases = items.filter { $0.kind == .typealias }
        #expect(aliases.map(\.name) == ["Alias", "IntBox", "JSON"])
        #expect(aliases.map(\.typename) == ["Real", "Box", "Dictionary"])
        #expect(aliases[1].accessibility == .public)
        let member = try #require(items.first { $0.name == "Container" }?.substructure?.first)
        #expect(member.kind == .typealias)
        #expect(member.name == "Element")
        #expect(member.typename == "Outer.Inner")
        #expect(member.accessibility == .private)
    }

    @Test("the parser leaves out an alias no extension can extend, and one local to a body")
    func skipsUnextendableAndLocalAliases() throws {
        let items = try #require(SyntaxStructure.create(from: """
            typealias Handler = () -> Void
            typealias Both = P1 & P2
            struct Real {
                func run() { typealias Local = Real }
                var value: Int { typealias InAccessor = Real; return 0 }
            }
            """)?.substructure)
        #expect(!items.contains { $0.kind == .typealias })
        #expect(items.first?.substructure?.contains { $0.kind == .typealias } == false)
    }

    @Test("a typealias is drawn by no format and counted as no member")
    func aliasesAreNotDrawn() throws {
        let source = "struct Real { typealias Element = Int\n var value: Int }\ntypealias Alias = Real"
        let types = try parsed(source, file: "A.swift").compactMap { TypeInfo(from: $0) }
        #expect(types.map(\.name) == ["Real"])
        #expect(types.first?.memberCount == 1)
        #expect(declaredIds(script(source, .plantuml, .all), .plantuml) == ["Real"])
        let graph = ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(format: .svg)).layoutGraph
        #expect(graph?.nodes.map(\.id) == ["Real"])
    }

    // MARK: - The issue's witnesses

    @Test("--merge-extensions folds an extension written through a typealias into the aliased type",
          arguments: [DiagramFormat.plantuml, .mermaid])
    func mergedIntoAliasedType(format: DiagramFormat) {
        let text = script(Self.throughAliases, format, .merged)
        #expect(declaredIds(text, format) == ["Outer", "Outer.Inner", "Real"])
        #expect(text.contains("viaInnerAlias"))
        #expect(text.contains("viaAlias"))
    }

    @Test("an extension written through a typealias gets its ext edge to the aliased type",
          arguments: [DiagramFormat.plantuml, .mermaid])
    func extEdgeToAliasedType(format: DiagramFormat) {
        let edges = extEdges(script(Self.throughAliases, format, .all))
        #expect(edges == ["Outer.Inner <.. Inner : ext", "Real <.. Alias : ext"])
    }

    @Test("two extensions through one typealias each get an edge to the aliased type, not to each other",
          arguments: [DiagramFormat.plantuml, .mermaid])
    func twoExtensionsThroughOneAlias(format: DiagramFormat) {
        let source = """
            struct Outer { struct Inner {} }
            typealias Inner = Outer.Inner
            extension Inner {}
            extension Inner {}
            """
        let edges = extEdges(script(source, format, .all))
        #expect(edges == ["Outer.Inner <.. Inner : ext", "Outer.Inner <.. Inner0 : ext"])
        #expect(declaredIds(script(source, format, .merged), format) == ["Outer", "Outer.Inner"])
    }

    @Test("SVG hangs a type nested in an extension through a typealias off the aliased type",
          arguments: [ExtensionVisualization.all, .merged])
    func svgNestedTypeHangsOffAliasedType(extensions: ExtensionVisualization) {
        let source = "struct Real {}\ntypealias Alias = Real\nextension Alias { struct Nested {} }"
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: .svg)
        let graph = ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
        #expect(graph?.edges.map { "\($0.sourceId) -> \($0.targetId)" } == ["Real -> Alias.Nested"])
    }

    @Test("PlantUML with --merge-extensions hangs a type nested through a typealias off the aliased type")
    func plantUMLMergedNestedType() {
        let source = "struct Real {}\ntypealias Alias = Real\nextension Alias { struct Nested {} }"
        #expect(script(source, .plantuml, .merged).contains("Real +-- Alias.Nested"))
    }

    /// ModA declares a public `Inner`; ModB declares its own `Outer.Inner` and an alias `Inner`
    /// of it. Inside ModB the module's own alias shadows the import, so the extension is `Outer.Inner`'s.
    @Test("a typealias that shadows an imported type keeps the extension off the imported type")
    func shadowingAliasIsNotTheImportedType() throws {
        let modA = try parsed("public struct Inner {}", file: "A.swift", module: "ModA")
        let modB = try parsed("""
            import ModA
            struct Outer { struct Inner {} }
            typealias Inner = Outer.Inner
            extension Inner { func fromB() {} }
            """, file: "B.swift", module: "ModB")
        let merged = Configuration(elements: ElementOptions(showExtensions: .merged), format: .plantuml)
        let text = DiagramScript(items: modA + modB, configuration: merged).text
        let importedBox = text.components(separatedBy: "class \"Inner\" as Inner ").dropFirst().first?
            .prefix { $0 != "}" } ?? ""
        #expect(!importedBox.contains("fromB"))
        let nestedBox = text.components(separatedBy: "as Outer.Inner ").dropFirst().first?.prefix { $0 != "}" } ?? ""
        #expect(nestedBox.contains("fromB"))

        let shown = DiagramScript(items: modA + modB, configuration: Configuration(format: .plantuml)).text
        #expect(extEdges(shown) == ["Outer.Inner <.. Inner0 : ext"])
    }

    /// SVG resolves a supertype through the same lookup; the text formats still write the name.
    @Test("SVG draws a supertype written through a typealias to the aliased protocol")
    func svgSupertypeThroughAlias() {
        let source = "protocol Proto {}\ntypealias Q = Proto\nstruct S: Q {}"
        let graph = ClassDiagramGenerator()
            .generateScript(for: source, with: Configuration(format: .svg)).layoutGraph
        #expect(graph?.edges.map { "\($0.sourceId) -> \($0.targetId)" } == ["S -> Proto"])
    }

    // MARK: - More alias shapes

    @Test("an alias of a bound generic, an alias chain and a nested alias are each followed")
    func moreAliasShapes() {
        let bound = "struct Box<T> {}\ntypealias IntBox = Box<Int>\nextension IntBox { func onlyInt() {} }"
        #expect(declaredIds(script(bound, .plantuml, .merged), .plantuml) == ["Box"])
        let chain = "struct Real {}\ntypealias A1 = A2\ntypealias A2 = Real\nextension A1 { func viaChain() {} }"
        #expect(declaredIds(script(chain, .plantuml, .merged), .plantuml) == ["Real"])
        let nested = "struct Real {}\nstruct Container { typealias Element = Real }\nextension Container.Element {}"
        #expect(extEdges(script(nested, .plantuml, .all)) == ["Real <.. Container.Element : ext"])
    }

    @Test("an extension through an alias of an outside type shares a box with the type's own extensions")
    func outsideTypeThroughAlias() {
        let source = """
            typealias JSON = [String: Int]
            extension JSON { func a() {} }
            extension [String: Int] { func b() {} }
            """
        #expect(declaredIds(script(source, .plantuml, .merged), .plantuml) == ["JSON"])
        // An outside type's extensions stay unlinked when drawn apart, however each is spelled.
        #expect(extEdges(script(source, .plantuml, .all)).isEmpty)
    }

    @Test("an alias that cycles is a type outside the diagram, not a hang")
    func aliasCycle() {
        // Swift rejects this; the lookup still has to end.
        let source = "typealias A = B\ntypealias B = A\nextension A {}\nextension B {}"
        #expect(declaredIds(script(source, .plantuml, .merged), .plantuml).count == 2)
    }

    /// Following `X` reaches `X.Y`, a member of `extension X`, whose own name is looked up from
    /// inside that extension, which needs `X` again. The lookup used to start that over at depth
    /// 0, and overflowed the stack.
    @Test("an alias that cycles through its extension's member ends",
          arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml, .svg], [ExtensionVisualization.all, .merged, .none])
    func aliasCycleThroughExtensionMember(format: DiagramFormat, mode: ExtensionVisualization) {
        // Swift rejects this; the lookup still has to end.
        let source = "typealias X = X.Y\nextension X {\n    typealias Y = Int\n    class Sub: Base {}\n}\nclass Base {}"
        #expect(!script(source, format, mode).isEmpty)
    }

    // MARK: - Access

    /// A `fileprivate` alias names its type only in its own file, so an extension in another
    /// file written with that name extends whatever else the name means there.
    @Test("a fileprivate alias in another file does not capture an extension's name")
    func fileprivateAliasInAnotherFile() throws {
        let aliasFile = try parsed("struct Real {}\nfileprivate typealias Alias = Real", file: "A.swift")
        let sameFile = try parsed("extension Alias { func here() {} }", file: "A.swift")
        let otherFile = try parsed("extension Alias { func there() {} }", file: "B.swift")
        #expect(mergedIds(of: aliasFile + sameFile) == ["Real"])
        #expect(mergedIds(of: aliasFile + otherFile) == ["Real", "Alias"])
    }

    /// Between modules an alias below `package` is invisible, so ModB's extension is of ModB's
    /// own `Alias` struct, not ModA's internal alias of `Real`.
    @Test("an internal alias in another module does not capture an extension's name")
    func internalAliasInAnotherModule() throws {
        let modA = try parsed("public struct Real {}\ntypealias Alias = Real", file: "A.swift", module: "ModA")
        let modB = try parsed("extension Alias { func fromB() {} }", file: "B.swift", module: "ModB")
        #expect(mergedIds(of: modA + modB) == ["Real", "Alias"])
        let publicAlias = try parsed(
            "public struct Real {}\npublic typealias Alias = Real", file: "A.swift", module: "ModA"
        )
        #expect(mergedIds(of: publicAlias + modB) == ["Real"])
    }

    // MARK: - Controls

    @Test("controls: the same shapes written without a typealias", arguments: [DiagramFormat.plantuml, .mermaid])
    func controls(format: DiagramFormat) {
        let direct = """
            struct Outer { struct Inner {} }
            extension Outer.Inner { func viaInnerAlias() {} }
            struct Real {}
            extension Real { func viaAlias() {} }
            """
        #expect(declaredIds(script(direct, format, .merged), format) == ["Outer", "Outer.Inner", "Real"])
        let edges = extEdges(script(direct, format, .all))
        #expect(edges == ["Outer.Inner <.. Outer.Inner0 : ext", "Real <.. Real1 : ext"])
    }
}
