import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Where supertype edges end, and how they are drawn, once a name read through a module resolves
/// (#124): through a typealias that `--merge-extensions` moves, onto a class that shares a name
/// with another module's protocol, past a box that only an extension spelled through a module
/// named, and onto an extension that stands in for a hidden type, however it spells it.
@Suite("Module-qualified supertype edges")
struct ModuleQualifiedEdgeTests {

    private func text(_ files: [(module: String?, source: String)], _ configuration: Configuration) throws -> String {
        DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration).text
    }

    private func graph(
        _ files: [(module: String?, source: String)], _ configuration: Configuration
    ) throws -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: configuration)
    }

    /// `ModA.Foo.Proto` is declared by ModB's extension of ModA's `Foo`. Merged, the alias is a
    /// member of `Foo`, and it is still ModA's `Foo.Proto`.
    @Test("a typealias in a qualified extension is still reached through the module once merged",
          arguments: [ExtensionVisualization.all, .merged])
    func mergedQualifiedAlias(extensions: ExtensionVisualization) throws {
        let modA = "public struct Foo {\n    public init() {}\n}\n\npublic protocol P {}\n"
        let modB = """
            import ModA

            extension ModA.Foo {
                typealias Proto = P
            }

            struct S: ModA.Foo.Proto {}
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let elements = ElementOptions(showExtensions: extensions)
        #expect(try graph(files, Configuration(elements: elements, format: .svg)).edgeEnds.contains("S -> P"))
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration(elements: elements)), containing: "<|")
        #expect(edges == ["P <|.. S : conforms to"])
    }

    /// ModA's protocol `Logger` is drawn first and keeps the id `Logger`; ModB's class is
    /// `Logger0`. The edge to it is a class's: inheritance, not conformance.
    @Test("an edge resolved onto a class is drawn as inheritance, beside a protocol of its name")
    func resolvedArrowIsTheTargets() throws {
        let modA = "public protocol Logger {}"
        let modB = "open class Logger {\n    public init() {}\n}"
        let modC = "import ModA\nimport ModB\n\nclass AppLogger: ModB.Logger {}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB), ("ModC", modC)]
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration()), containing: "AppLogger")
            .filter { $0.contains("<|") }
        #expect(edges == ["Logger0 <|-- AppLogger : inherits"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("AppLogger -> Logger_1"))
    }

    /// ModB both extends ModA's `Base` and subclasses it. The `extension ModA.Base` box has the
    /// name `ModA.Base`, but it is not the class, so the edge ends on `Base`, as in SVG.
    @Test("a name only a qualified extension's box has ends on the type it extends")
    func qualifiedExtensionBoxIsNotTheType() throws {
        let modA = "open class Base {\n    public init() {}\n}"
        let modB = """
            import ModA

            extension ModA.Base {
                func helper() {}
            }

            class Sub: ModA.Base {}
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration()), containing: "Sub")
            .filter { $0.contains("<|") }
        #expect(edges == ["Base <|-- Sub : inherits"])
        #expect(try graph(files, Configuration(format: .svg)).edgeEnds.contains("Sub -> Base"))
    }

    @Test("an excluded qualified extension stays hidden when it would merge into a drawn type")
    func excludedQualifiedExtensionOfDrawnType() throws {
        let modA = "public struct Foo {\n    public init() {}\n}"
        let modB = "import ModA\n\nextension ModA.Foo {\n    func secret() {}\n}\n"
        let elements = ElementOptions(showExtensions: .merged, exclude: ["ModA.Foo"])
        let graph = try graph([("ModA", modA), ("ModB", modB)], Configuration(elements: elements, format: .svg))
        #expect(graph.nodeIds == ["Foo"])
        #expect(graph.owner(of: "secret") == nil)
    }

    /// `Hidden` is internal and drawn only through `extension HA`. Both edges end on that box,
    /// whether they name the type or the alias, in every format, as conformances: the hidden
    /// type is a protocol.
    @Test("an extension spelled through a typealias stands in for an edge that names the type")
    func aliasSpelledStandInForDirectName() throws {
        let app = """
            protocol Hidden {}
            typealias HA = Hidden

            extension HA {
                public func viaAlias() {}
            }

            public struct A: Hidden {}
            public struct B: HA {}
            """
        let publicOnly = ElementOptions(havingAccessLevel: [.public, .open])
        let files: [(module: String?, source: String)] = [(nil, app)]
        #expect(try graph(files, Configuration(elements: publicOnly, format: .svg)).edgeEnds.sorted()
            == ["A -> HA", "B -> HA"])
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration(elements: publicOnly)), containing: "<|")
        #expect(edges.sorted() == ["HA <|.. A : conforms to", "HA <|.. B : conforms to"])
    }
}
