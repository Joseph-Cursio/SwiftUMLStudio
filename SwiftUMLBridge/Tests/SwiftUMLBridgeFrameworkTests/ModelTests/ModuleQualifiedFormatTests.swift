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

    /// ModB declares its own `Base`, so a box has that name, and the text formats end the edge
    /// on it, as they always have, though Swift means ModA's `Foo.Base`, where SVG ends it.
    @Test("a supertype named like a drawn box still ends on that box in the text formats")
    func nameOfADrawnBoxWins() throws {
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
        #expect(edges == ["Base <|-- ModA.Foo.Child : inherits"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("ModA.Foo.Child -> Foo.Base"))
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
}
