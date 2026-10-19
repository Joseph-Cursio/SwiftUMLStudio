import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// What exclude patterns and the text formats' supertype edges do with a module-qualified name
/// (#124): the patterns match the type it means, and PlantUML, Mermaid and Nomnoml, which end a
/// supertype edge on a name, draw it as they did before.
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
        let qualified = pattern == "Q" ? "ModA.Q <" : "ModA.QAlias <"
        #expect(try lines(files, Configuration(format: .plantuml), containing: qualified).count == 1)
        #expect(try lines(files, Configuration(relationships: excluded, format: .plantuml), containing: qualified)
            .isEmpty)
        let target = pattern == "Q" ? "ModA.Foo -> Q" : "S -> Q"
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains(target))
        #expect(try graph(files, Configuration(relationships: excluded, format: .svg)).edgeEnds.contains(target)
            == false)
    }

    // MARK: - Supertypes in the text formats

    /// PlantUML, Mermaid and Nomnoml end a supertype edge on a name, the first box of that name,
    /// so they read no module qualifier and end it where they did before #124. SVG ends it on the
    /// declaration.
    @Test("a supertype inside a qualified extension is drawn as before in text, on the member in SVG")
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
        #expect(edges == ["Base <|-- ModA.Foo.Child : inherits"])
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
