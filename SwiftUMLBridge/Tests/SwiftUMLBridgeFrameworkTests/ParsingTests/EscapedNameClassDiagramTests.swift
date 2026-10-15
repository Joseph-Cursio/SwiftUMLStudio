import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftUMLBridgeFramework

/// `` `Plain` `` and `Plain` are one identifier, so a class diagram draws a name escaped in one place
/// and not in another as one name. `SyntaxStructureBuilder` read each name as written, so
/// `` extension `Plain` `` was neither merged into nor linked to `struct Plain`, and an edge to a
/// supertype written `` `Base` `` ended on a node of its own. A raw identifier (`` `Foo Bar` ``) or a
/// keyword (`` `class` ``) needs its backticks wherever it is written, and keeps them (#123).
@Suite("Class-diagram names written with backticks")
struct EscapedNameClassDiagramTests {

    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml, .svg]

    // Each witness escapes a name on one side only: where it is declared, extended, inherited from
    // or used as a type. All of them compile, and so does each with its backticks removed.
    static let extendedPlain = "struct Plain {}\nextension `Plain` { func get() -> Int { 0 } }"
    static let extendedTicked = "struct `Ticked` {}\nextension Ticked { func get() -> Int { 0 } }"
    static let extendedNested = "struct Outer { struct Inner {} }\nextension `Outer`.`Inner` { func get() {} }"
    static let boundArgument = "struct Plain<T> {}\nextension Plain<`Int`> { func get() -> Int { 0 } }"
    static let supertypes = "class Base {}\nclass Sub: `Base` {}\nprotocol Proto {}\nstruct Conformer: `Proto` {}"
    static let nestedInExtension = "struct Plain {}\nextension `Plain` { struct Inner {} }"
    static let members = """
        struct Plain {
            var `count`: [`Plain`] = []
            func `helper`() async {}
        }
        enum Kind {
            case `first`
        }
        """
    static let generics = "protocol Proto {}\nstruct Box<`Element`: `Proto`> { var item: `Element` }"
    static let attribute = "import Observation\n@`Observable` final class Model {}"

    static let witnesses = [
        extendedPlain, extendedTicked, extendedNested, boundArgument, supertypes, nestedInExtension, members,
        generics, attribute
    ]

    private func script(
        _ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all
    ) -> DiagramScript {
        let configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        return ClassDiagramGenerator().generateScript(for: source, with: configuration)
    }

    private func lines(
        _ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all
    ) -> [String] {
        script(source, format, extensions).text.split(separator: "\n").map(String.init)
    }

    /// The title of each box `source` draws in `format`, in drawing order.
    private func titles(
        _ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all
    ) throws -> [String] {
        let drawn = script(source, format, extensions)
        let lines = drawn.text.split(separator: "\n")
        switch format {
        case .plantuml:
            return lines.filter { $0.hasPrefix("class \"") }.map { String($0.dropFirst(7).prefix { $0 != "\"" }) }
        case .mermaid:
            return lines.filter { $0.hasPrefix("class ") }.compactMap { $0.split(separator: "\"").dropFirst().first }
                .map(String.init)
        case .nomnoml: return try NomnomlGraph(parsing: drawn.text).nodes.map(\.title)
        default: return drawn.layoutGraph?.nodes.map(\.label) ?? []
        }
    }

    private func svgGraph(_ source: String, _ extensions: ExtensionVisualization = .all) -> LayoutGraph? {
        script(source, .svg, extensions).layoutGraph
    }

    // MARK: - The issue's witnesses

    @Test("a name escaped on one side draws what it draws unescaped", arguments: witnesses, formats)
    func sameAsUnescaped(source: String, format: DiagramFormat) {
        let unescaped = source.replacingOccurrences(of: "`", with: "")
        for extensions in [ExtensionVisualization.all, .merged] {
            #expect(script(source, format, extensions).text == script(unescaped, format, extensions).text)
        }
    }

    @Test("--merge-extensions folds the extension into its type's box", arguments: formats)
    func mergedIntoOneBox(format: DiagramFormat) throws {
        #expect(try titles(Self.extendedPlain, format, .merged) == ["Plain"])
        #expect(try titles(Self.extendedTicked, format, .merged) == ["Ticked"])
    }

    @Test("the default diagram links the extension to its type", arguments: [DiagramFormat.plantuml, .mermaid])
    func extEdge(format: DiagramFormat) {
        #expect(lines(Self.extendedPlain, format).filter { $0.contains("<..") } == ["Plain <.. Plain0 : ext"])
        #expect(lines(Self.extendedTicked, format).filter { $0.contains("<..") } == ["Ticked <.. Ticked0 : ext"])
        #expect(lines(Self.extendedNested, format).filter { $0.contains("<..") }
            == ["Outer.Inner <.. Outer.Inner0 : ext"])
    }

    @Test("nomnoml links the extension to its type")
    func nomnomlExtEdge() throws {
        let graph = try NomnomlGraph(parsing: script(Self.extendedPlain, .nomnoml).text)
        #expect(graph.nodes.map(\.id) == ["Plain", "Plain0"])
        #expect(graph.edges.map { [$0.start, $0.type, $0.end] } == [["Plain0", "-->", "Plain"]])
    }

    @Test("a supertype written with backticks is the declared type", arguments: [DiagramFormat.plantuml, .mermaid])
    func supertypeEdges(format: DiagramFormat) {
        #expect(lines(Self.supertypes, format).filter { $0.contains("<|") }
            == ["Base <|-- Sub : inherits", "Proto <|.. Conformer : conforms to"])
    }

    @Test("nomnoml and SVG end a supertype edge written with backticks on the declared type")
    func supertypeEdgesNomnomlAndSVG() {
        #expect(lines(Self.supertypes, .nomnoml).filter { $0.contains(":>") }
            == ["[Sub] -:> inherits [Base]", "[Conformer] --:> conforms to [Proto]"])
        #expect(svgGraph(Self.supertypes)?.edgeEnds == ["Sub -> Base", "Conformer -> Proto"])
    }

    @Test("SVG folds the extension into its type's node, and hangs its nested type off that node")
    func svgExtendedType() {
        #expect(svgGraph(Self.extendedPlain, .merged)?.nodeIds == ["Plain"])
        #expect(svgGraph(Self.nestedInExtension)?.edgeEnds == ["Plain -> Plain.Inner"])
        #expect(svgGraph(Self.nestedInExtension, .merged)?.edgeEnds == ["Plain -> Plain.Inner"])
    }

    @Test("members, cases, generics and attributes are listed by name")
    func memberNames() {
        let members = lines(Self.members, .plantuml)
        #expect(members.contains("  ~count : [Plain]"))
        #expect(members.contains("  ~helper async "))
        #expect(members.contains("  ~first "))
        let generics = lines(Self.generics, .plantuml)
        #expect(generics.contains { $0.contains(" as Box<Element: Proto> ") })
        #expect(generics.contains("  ~item : Element "))
        let attribute = lines(Self.attribute, .plantuml)
        #expect(attribute.contains { $0.contains(">> <<Observable>> {") })
        #expect(attribute.contains("Observable <|-- Model : inherits"))
        #expect(lines(Self.boundArgument, .plantuml).contains { $0.contains(" as Plain0<Int> ") })
    }

    // MARK: - typeReferenceName

    /// The receiver of the call `source` writes, as in `Receiver.make()`.
    private func receiver(_ source: String) throws -> ExprSyntax {
        let file = Parser.parse(source: source)
        let call = try #require(file.statements.first?.item.as(FunctionCallExprSyntax.self))
        return try #require(call.calledExpression.as(MemberAccessExprSyntax.self)?.base)
    }

    @Test("a call receiver written with backticks names the type", arguments: [
        ("`Plain`.make()", "Plain"),
        ("`Outer`.`Inner`.make()", "Outer.Inner"),
        ("`Plain`<Int>.make()", "Plain"),
        ("Plain.make()", "Plain"),
        ("Outer.Inner.make()", "Outer.Inner")
    ])
    func typeReference(source: String, expected: String) throws {
        #expect(try receiver(source).typeReferenceName == expected)
    }

    @Test("a value written with backticks is still a value", arguments: ["`plain`.make()", "plain.make()"])
    func valueReference(source: String) throws {
        #expect(try receiver(source).typeReferenceName == nil)
    }

    // MARK: - Controls: names that need their backticks keep them

    @Test("a raw identifier or keyword type keeps its backticks", arguments: ["`Foo Bar`", "`class`"])
    func neededBackticks(name: String) throws {
        let source = "struct \(name) {}\nextension \(name) { func get() -> Int { 0 } }"
        for format in [DiagramFormat.plantuml, .mermaid] {
            #expect(lines(source, format).filter { $0.contains("<..") } == ["\(name) <.. \(name)0 : ext"])
        }
        for format in Self.formats {
            #expect(try titles(source, format, .merged) == [name])
        }
    }

    @Test("a raw identifier or keyword supertype keeps its backticks")
    func neededBackticksSupertype() {
        let source = "class `Base Class` {}\nclass Sub: `Base Class` {}\nprotocol `protocol` {}\n"
            + "struct Conformer: `protocol` {}"
        #expect(lines(source, .plantuml).filter { $0.contains("<|") }
            == ["`Base Class` <|-- Sub : inherits", "`protocol` <|.. Conformer : conforms to"])
        #expect(svgGraph(source)?.edgeEnds == ["Sub -> `Base Class`", "Conformer -> `protocol`"])
    }

    @Test("a keyword member or case keeps its backticks")
    func neededBackticksMembers() {
        let source = """
            struct Plain {
                var `default`: Int = 0
                func `class`() {}
            }
            enum Kind {
                case `default`
            }
            """
        let plantUML = lines(source, .plantuml)
        #expect(plantUML.contains("  ~`default` : Int"))
        #expect(plantUML.contains("  ~`class` "))
        #expect(plantUML.contains("  ~`default` "))
    }

    @Test("controls: the witnesses' names written without backticks")
    func unescaped() throws {
        let supertypes = "class Base {}\nclass Sub: Base {}\nprotocol Proto {}\nstruct Conformer: Proto {}"
        #expect(lines(supertypes, .plantuml).filter { $0.contains("<|") }
            == ["Base <|-- Sub : inherits", "Proto <|.. Conformer : conforms to"])
        #expect(svgGraph(supertypes)?.edgeEnds == ["Sub -> Base", "Conformer -> Proto"])
        let plain = "struct Plain {}\nextension Plain { func get() -> Int { 0 } }"
        #expect(lines(plain, .plantuml).filter { $0.contains("<..") } == ["Plain <.. Plain0 : ext"])
        #expect(try titles(plain, .nomnoml, .merged) == ["Plain"])
        let nested = "struct Plain {}\nextension Plain { struct Inner {} }"
        #expect(svgGraph(nested)?.edgeEnds == ["Plain -> Plain.Inner"])
    }
}
