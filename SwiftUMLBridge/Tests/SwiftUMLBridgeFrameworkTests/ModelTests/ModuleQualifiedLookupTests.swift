import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// How `TypeLookup` reads a module qualifier (#124): which modules a qualifier names, which
/// declarations a module owns, when a type keeps a qualifier from being read as a module, which
/// extension stands in for a hidden type, and what the text formats do with a qualified name.
@Suite("Module qualifiers in the type lookup")
struct ModuleQualifiedLookupTests {

    private static let modA = """
        public struct Foo {
            public init() {}
            public struct Inner {}
        }
        """

    private static let merged = Configuration(elements: ElementOptions(showExtensions: .merged), format: .svg)

    private func graph(
        _ files: [(module: String?, source: String)], _ configuration: Configuration = Self.merged
    ) throws -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: configuration)
    }

    private func lines(
        _ files: [(module: String?, source: String)], _ configuration: Configuration, containing marker: String
    ) throws -> [String] {
        let script = DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration)
        return ClassDiagramIds.lines(of: script.text, containing: marker)
    }

    // MARK: - Which module a qualifier names

    /// The names `swift package describe --type json` reports as each target's `c99name`.
    @Test("a target's module name is derived as SwiftPM derives it", arguments: [
        ("my-lib", "my_lib"), ("2D", "_D"), ("1st-party", "_st_party"), ("9", "_"), ("a b.c", "a_b_c"),
        ("Plain", "Plain")
    ])
    func c99Name(target: String, module: String) {
        #expect(ModuleQualifiers.c99Name(of: target) == module)
    }

    /// `Swift` is no module of the diagram, so `Swift.Result` is not App's own `Result`.
    @Test("a qualifier that names no module of the diagram is not stripped")
    func unknownQualifierKeepsItsType() throws {
        let app = """
            struct Result {}

            extension Swift.Result {
                func fromApp() {}
            }
            """
        let graph = try graph([("App", app)])
        #expect(graph.owner(of: "fromApp") == "Swift.Result")
    }

    // MARK: - Which declarations a module owns

    /// ModB adds `Nested` to ModA's `Foo`, so in Swift ModC can write it `ModA.Foo.Nested`: the
    /// qualifier finds `Foo`, and `Nested` is a member of that `Foo` wherever it was declared.
    @Test("a type another module nests in a module's type is reached through that module")
    func nestedByAnotherModule() throws {
        let modA = "public struct Foo {\n    public init() {}\n}"
        let modB = """
            import ModA

            extension Foo {
                public struct Nested {
                    public init() {}
                }
            }
            """
        let modC = """
            import ModA
            import ModB

            struct Foo {}

            extension ModA.Foo.Nested {
                func fromC() {}
            }
            """
        let graph = try graph([("ModA", modA), ("ModB", modB), ("ModC", modC)])
        #expect(graph.owner(of: "fromC") == "Foo.Nested")
    }

    // MARK: - When a type keeps the qualifier a type

    /// Core's `enum Analytics` is a namespace App's file does not import, so there `Analytics` is
    /// the module. A type named like the qualifier counts only from the writer's own module or the
    /// module the qualifier names.
    @Test("a type in a third module does not keep the qualifier from naming a module")
    func thirdModuleTypeDoesNotShadow() throws {
        let analytics = "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public static let screenKey = \"screen\"\n}"
        let app = """
            import Analytics

            struct Event {}

            extension Analytics.Event {
                func track() {}
            }
            """
        let graph = try graph([("Analytics", analytics), ("Core", core), ("App", app)])
        #expect(graph.owner(of: "track") == "Event")
    }

    /// Module Foo declares a type `Foo`, so in Swift `Foo.Bar` is that type's `Bar`, not the
    /// module's top-level one.
    @Test("a module's type of its own name is read before the module")
    func moduleNamedLikeItsType() throws {
        let foo = """
            public struct Foo {
                public struct Bar {}
            }

            public struct Bar {}
            """
        let app = """
            import Foo

            extension Foo.Bar {
                func fromApp() {}
            }
            """
        let graph = try graph([("Foo", foo), ("App", app)])
        #expect(graph.owner(of: "fromApp") == "Foo.Bar")
    }

    // MARK: - Stand-ins for a hidden type

    /// Only internal declarations are drawn, so ModA's public `Foo` is hidden while its internal
    /// `Inner` and both extensions are drawn. The stand-in is whichever extension comes first, in
    /// either spelling, and `--merge-extensions` merges the other into it.
    @Test("the stand-in is the first extension of the hidden type, in either spelling", arguments: [
        (["ModA", "ModB"], "Foo"), (["ModB", "ModA"], "ModA.Foo")
    ])
    func standInOrder(order: [String], standIn: String) throws {
        let sources = [
            "ModA": Self.modA.replacingOccurrences(of: "public struct Inner", with: "struct Inner")
                + "\nextension Foo {\n    func fromA() {}\n}\n",
            "ModB": "import ModA\n\nextension ModA.Foo {\n    func fromB() {}\n}\n"
        ]
        let files = order.map { (module: Optional($0), source: sources[$0] ?? "") }
        let internalOnly = ElementOptions(havingAccessLevel: [.internal])
        let shown = try graph(files, Configuration(elements: internalOnly, format: .svg))
        #expect(shown.edgeEnds == ["\(standIn) -> Foo.Inner"])
        #expect(try lines(files, Configuration(elements: internalOnly, format: .plantuml), containing: "+--")
            == ["\(standIn) +-- Foo.Inner"])

        let mergedInternal = ElementOptions(havingAccessLevel: [.internal], showExtensions: .merged)
        let merged = try graph(files, Configuration(elements: mergedInternal, format: .svg))
        #expect(merged.owner(of: "fromA") == standIn)
        #expect(merged.owner(of: "fromB") == standIn)
        #expect(merged.edgeEnds == ["\(standIn) -> Foo.Inner"])
    }

    // MARK: - Excludes

    @Test("dependency.exclude matches the type a qualified extension extends")
    func dependencyExclude() throws {
        let modB = "import ModA\n\nextension ModA.Foo.Inner {\n    func innerFromB() {}\n}\n"
        let excluded = RelationshipOptions(dependency: Relationship(label: "ext", exclude: ["Foo.Inner"]))
        let edges = try lines(
            [("ModA", Self.modA), ("ModB", modB)], Configuration(relationships: excluded), containing: " : ext"
        )
        #expect(edges.isEmpty)
    }

    @Test("realize.exclude matches a protocol named through its module")
    func realizeExclude() throws {
        let modA = Self.modA + "\npublic protocol Q {}\n"
        let modB = "import ModA\n\nextension ModA.Foo: ModA.Q {}\n"
        let excluded = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: ["Q"]))
        let graph = try graph([("ModA", modA), ("ModB", modB)], Configuration(relationships: excluded, format: .svg))
        #expect(graph.edgeEnds.contains { $0.hasSuffix("-> Q") } == false)
    }

    // MARK: - Supertypes in the text formats

    /// PlantUML, Mermaid and Nomnoml end a supertype edge on a name, the first box of that name,
    /// so they read no module qualifier and end it where they did before #124. SVG ends it on the
    /// declaration.
    @Test("a supertype inside a qualified extension ends on no name nothing declares")
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
        #expect(edges.contains { $0.hasPrefix("ModA.Foo.Base") } == false)
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("ModA.Foo.Child -> Foo.Base"))
    }

    /// App declares its own `Store`, so the bare name would end the edge on App's box; Swift
    /// conforms `Cache` to Lib's.
    @Test("a qualified typealias supertype is not moved onto another module's type of its name")
    func qualifiedAliasSupertype() throws {
        let lib = "public protocol Store {}\npublic typealias StoreType = Store\n"
        let app = "import Lib\n\nprotocol Store {}\n\nstruct Cache: Lib.StoreType {}\n"
        let files: [(module: String?, source: String)] = [("Lib", lib), ("App", app)]
        let edges = try lines(files, Configuration(format: .plantuml), containing: "Cache")
            .filter { $0.contains("<|") }
        #expect(edges == ["Lib.StoreType <|-- Cache : inherits"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("Cache -> Store"))
    }
}
