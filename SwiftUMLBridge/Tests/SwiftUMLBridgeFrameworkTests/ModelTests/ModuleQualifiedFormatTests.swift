import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// What exclude patterns and the text formats' supertype edges do with a module-qualified name
/// (#124): the patterns match the type it means, and PlantUML, Mermaid and Nomnoml end the edge on
/// that type's box when no box has the name as written, as SVG does.
@Suite("Module qualifiers in excludes and the text formats")
struct ModuleQualifiedFormatTests {

    private static let modA = """
        public struct Foo {
            public init() {}
            public struct Inner {}
        }
        """

    private func graph(
        _ files: [(module: String?, source: String)], _ configuration: Configuration
    ) throws -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: configuration)
    }

    private func lines(
        _ files: [(module: String?, source: String)], _ configuration: Configuration, containing marker: String
    ) throws -> [String] {
        let script = DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration)
        return ClassDiagramIds.lines(of: script.text, containing: marker)
    }

    // MARK: - Excludes

    @Test("dependency.exclude matches the type a qualified extension extends")
    func dependencyExclude() throws {
        let modB = "import ModA\n\nextension ModA.Foo.Inner {\n    func innerFromB() {}\n}\n"
        let files: [(module: String?, source: String)] = [("ModA", Self.modA), ("ModB", modB)]
        let excluded = RelationshipOptions(dependency: Relationship(label: "ext", exclude: ["Foo.Inner"]))
        #expect(try lines(files, Configuration(), containing: " : ext") == ["Foo.Inner <.. ModA.Foo.Inner : ext"])
        #expect(try lines(files, Configuration(relationships: excluded), containing: " : ext").isEmpty)
    }

    @Test("realize.exclude matches a protocol or typealias named through its module, in every format",
          arguments: ["Q", "QAlias"])
    func realizeExclude(pattern: String) throws {
        let modA = Self.modA + "\npublic protocol Q {}\npublic typealias QAlias = Q\n"
        let modB = "import ModA\n\nextension ModA.Foo: ModA.Q {}\n\nstruct S: ModA.QAlias {}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let excluded = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: [pattern]))
        let edge = pattern == "Q" ? "Q <|.. ModA.Foo : conforms to" : "Q <|.. S : conforms to"
        #expect(try lines(files, Configuration(format: .plantuml), containing: "<|..").contains(edge))
        #expect(try lines(files, Configuration(relationships: excluded, format: .plantuml), containing: "<|..")
            .contains(edge) == false)
        let target = pattern == "Q" ? "ModA.Foo -> Q" : "S -> Q"
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains(target))
        #expect(try graph(files, Configuration(relationships: excluded, format: .svg)).edgeEnds.contains(target)
            == false)
    }

    // MARK: - Supertypes in the text formats

    /// No box is named `Base`, so instead of an undeclared `Base` node the text formats end the
    /// edge on the box of the type Swift means, ModA's `Foo.Base`, as SVG does.
    @Test("a supertype inside a qualified extension ends on the extended type's member in every format")
    func supertypeInQualifiedExtension() throws {
        let modA = """
            public struct Foo {
                public init() {}
                open class Base {
                    public init() {}
                }
            }
            """
        let modB = "import ModA\n\nextension ModA.Foo {\n    class Child: Base {}\n}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let edges = try lines(files, Configuration(format: .plantuml), containing: "<|--")
        #expect(edges == ["Foo.Base <|-- ModA.Foo.Child : inherits"])
        let nomnoml = try lines(files, Configuration(format: .nomnoml), containing: "-:>")
        #expect(nomnoml == ["[ModA.Foo.Child] -:> inherits [Foo.Base]"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("ModA.Foo.Child -> Foo.Base"))
    }

    /// ModB declares its own `Base`, but inside `extension ModA.Foo` Swift looks `Base` up among
    /// `Foo`'s members first, so the text formats end the edge on ModA's `Foo.Base`, as SVG does.
    @Test("a member of a qualified extension is found before a box of its short name")
    func memberBeforeShortName() throws {
        let modA = """
            public struct Foo {
                public init() {}
                open class Base {
                    public init() {}
                }
            }
            """
        let modB = "import ModA\n\nfinal class Base {}\n\nextension ModA.Foo {\n    class Child: Base {}\n}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let edges = try lines(files, Configuration(format: .plantuml), containing: "<|--")
        #expect(edges == ["Foo.Base <|-- ModA.Foo.Child : inherits"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("ModA.Foo.Child -> Foo.Base"))
    }

    /// App's own `Store` is the first box named `Store`. `StoreType` is Lib's alias of Lib's
    /// `Store`, so the edge ends on Lib's box, `Store0`, in the text formats as in SVG, though
    /// App's box has the name it comes to.
    @Test("a supertype ends on the box SVG ends it on, though another box has the name it comes to")
    func nameOfADrawnBoxDoesNotWin() throws {
        let app = "import Lib\n\nprotocol Store {}\n\nstruct Cache: StoreType {}\n"
        let lib = "public protocol Store {}\npublic typealias StoreType = Store\n"
        let files: [(module: String?, source: String)] = [("App", app), ("Lib", lib)]
        let edges = try lines(files, Configuration(format: .plantuml), containing: "Cache")
            .filter { $0.contains("<|") }
        #expect(edges == ["Store0 <|.. Cache : conforms to"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("Cache -> Store_1"))
    }

    /// App declares its own `Store`, so a bare `Store` would end the edge on App's box; Swift
    /// conforms `Cache` to Lib's, which is the first `Store` declared here and keeps that id.
    @Test("a qualified typealias supertype ends on the aliased type's box, not another module's")
    func qualifiedAliasSupertype() throws {
        let lib = "public protocol Store {}\npublic typealias StoreType = Store\n"
        let app = "import Lib\n\nprotocol Store {}\n\nstruct Cache: Lib.StoreType {}\n"
        let files: [(module: String?, source: String)] = [("Lib", lib), ("App", app)]
        let edges = try lines(files, Configuration(format: .plantuml), containing: "Cache")
            .filter { $0.contains("<|") }
        #expect(edges == ["Store <|.. Cache : conforms to"])
        let swapped = try lines([("App", app), ("Lib", lib)], Configuration(format: .plantuml), containing: "Cache")
            .filter { $0.contains("<|") }
        #expect(swapped == ["Store0 <|.. Cache : conforms to"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("Cache -> Store"))
    }

    // MARK: - Hidden nested types

    /// With nested types hidden ModB's own `Foo.V` is not drawn, but it is what `Foo.V` means in
    /// ModB, never the `typealias V` ModB's extension of ModA's `Foo` declares, however that
    /// extension spells the type: the edge finds no end, as when there is no such alias.
    @Test("a hidden nested type is what its name means, not another module's member typealias", arguments: [
        "typealias FA = ModA.Foo\n\nextension FA {\n    typealias V = ModA.Base\n}\n",
        "extension ModA.Foo {\n    typealias V = ModA.Base\n}\n"
    ])
    func hiddenNestedTypeBeforeMemberAlias(spelling: String) throws {
        let modA = "public struct Foo {\n    public init() {}\n}\n\nopen class Base {\n    public init() {}\n}\n"
        let modB = "import ModA\n\nstruct Foo {\n    class V {}\n}\n\n\(spelling)\nfinal class C11: Foo.V {}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        for mode in [ExtensionVisualization.all, .merged] {
            let elements = ElementOptions(showNestedTypes: false, showExtensions: mode)
            for format in [DiagramFormat.plantuml, .mermaid] {
                let edges = try lines(files, Configuration(elements: elements, format: format), containing: "<|--")
                #expect(edges.map { $0.trimmingCharacters(in: .whitespaces) } == ["Foo.V <|-- C11 : inherits"],
                        "\(mode) \(format)")
            }
            let nomnoml = try lines(files, Configuration(elements: elements, format: .nomnoml), containing: "-:>")
            #expect(nomnoml == ["[C11] -:> inherits [Foo.V]"], "\(mode)")
            let svg = try graph(files, Configuration(elements: elements, format: .svg))
            #expect(svg.edges.filter { $0.sourceId == "C11" }.isEmpty, "\(mode)")
        }
    }

    /// ModA cannot see ModB, so in ModA `Foo.V` is ModA's own alias of `Base`, never the class
    /// ModB's `extension ModA.Foo` nests in `Foo`: hidden and merged into `Foo`, that class ranks
    /// in ModB, as it does drawn, wherever ModA writes the name.
    @Test("another module's hidden nested type does not shadow the type module's own alias", arguments: [
        ["public struct Foo {\n    public init() {}\n}\n\nopen class Base {\n    public init() {}\n}\n",
         "extension Foo {\n    public typealias V = Base\n}\n",
         "final class UseA: Foo.V {}\n"],
        ["public struct Foo {\n    public init() {}\n    public typealias V = Base\n}\n\n"
            + "open class Base {\n    public init() {}\n}\n\nfinal class UseA: Foo.V {}\n"]
    ])
    func hiddenNestedTypeOfOtherModule(modA: [String]) throws {
        let modB = "import ModA\n\nextension ModA.Foo {\n    open class V {\n        public init() {}\n    }\n}\n"
        let files: [(module: String?, source: String)] = modA.map { ("ModA", $0) } + [("ModB", modB)]
        for mode in [ExtensionVisualization.all, .merged] {
            let elements = ElementOptions(showNestedTypes: false, showExtensions: mode)
            for format in [DiagramFormat.plantuml, .mermaid] {
                let edges = try lines(files, Configuration(elements: elements, format: format), containing: "<|--")
                #expect(edges.map { $0.trimmingCharacters(in: .whitespaces) } == ["Base <|-- UseA : inherits"],
                        "\(mode) \(format)")
            }
            let nomnoml = try lines(files, Configuration(elements: elements, format: .nomnoml), containing: "-:>")
            #expect(nomnoml == ["[UseA] -:> inherits [Base]"], "\(mode)")
            let svg = try graph(files, Configuration(elements: elements, format: .svg))
            #expect(svg.edgeEnds.contains("UseA -> Base"), "\(mode)")
        }
    }
}
