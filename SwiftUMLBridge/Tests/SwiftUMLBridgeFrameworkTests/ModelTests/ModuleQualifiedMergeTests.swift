import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// What `--merge-extensions` and the lookup do with members of an extension spelled through a
/// module (#124): a typealias it declares, a type nested in it, an extension `elements.exclude`
/// hides, a conformance it repeats, and a nested typealias an exclude pattern names.
@Suite("Module-qualified extensions under merging and excludes")
struct ModuleQualifiedMergeTests {

    private static let merged = ElementOptions(showExtensions: .merged)

    private func text(_ files: [(module: String?, source: String)], _ configuration: Configuration) throws -> String {
        DiagramScript(items: try moduleQualifiedItems(files), configuration: configuration).text
    }

    private func graph(
        _ files: [(module: String?, source: String)], _ configuration: Configuration
    ) throws -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(files), configuration: configuration)
    }

    /// ModB has its own `Coordinator` with a nested `Child`, and adds a `Child` alias to ModA's
    /// `Coordinator` in another file. There `Coordinator.Child` is still ModB's nested class.
    @Test("an alias added to another module's type does not take over the module's own member",
          arguments: [ExtensionVisualization.all, .merged])
    func ownMemberBeforeAddedAlias(extensions: ExtensionVisualization) throws {
        let modA = """
            open class Coordinator {
                public init() {}
            }

            open class ChildCoordinator {
                public init() {}
            }
            """
        let own = "class Coordinator {\n    class Child {}\n}\n"
        let app = """
            import ModA

            extension ModA.Coordinator {
                typealias Child = ModA.ChildCoordinator
            }

            final class SettingsCoordinator: Coordinator.Child {}
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", own), ("ModB", app)]
        let elements = ElementOptions(showExtensions: extensions)
        let svg = try graph(files, Configuration(elements: elements, format: .svg))
        // ModB's `Coordinator` is `Coordinator_1`; its nested `Child` keeps the id `Coordinator.Child`.
        #expect(svg.edgeEnds.contains("Coordinator_1 -> Coordinator.Child"))
        #expect(svg.edgeEnds.contains("SettingsCoordinator -> Coordinator.Child"))
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration(elements: elements)), containing: "<|--")
        #expect(edges.filter { $0.contains("SettingsCoordinator") }
            == ["Coordinator.Child <|-- SettingsCoordinator : inherits"])
    }

    /// Merged, the alias `Proto` moves into ModA's `Foo`, and `Inner`, nested in the extension,
    /// still means it, not ModB's own `Proto`.
    @Test("a type nested in a merged qualified extension still sees the extension's alias")
    func nestedTypeSeesMergedAlias() throws {
        let modA = "public struct Foo {\n    public init() {}\n}\n\npublic protocol Real {}\n"
        let modB = """
            import ModA

            protocol Proto {}

            extension ModA.Foo {
                typealias Proto = Real
                struct Inner: Proto {}
            }
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let edges = ClassDiagramIds.lines(
            of: try text(files, Configuration(elements: Self.merged)), containing: "Inner"
        ).filter { $0.contains("<|") }
        #expect(edges == ["Real <|.. ModA.Foo.Inner : conforms to"])
        #expect(try graph(files, Configuration(elements: Self.merged, format: .svg)).edgeEnds
            .contains("ModA.Foo.Inner -> Real"))
    }

    /// `ModA.*` hides the extensions written through the module, whether of a hidden type, which
    /// has a plain `extension Foo` to merge into, or of a drawn one written through an alias.
    @Test("an extension excluded by its module spelling stays hidden under merging")
    func excludedThroughModuleStaysHidden() throws {
        let modA = """
            struct Foo {}

            extension Foo {
                public func visible() {}
            }

            extension ModA.Foo {
                public func secret() {}
            }

            public struct Bar {}
            """
        let modB = "import ModA\n\ntypealias BA = ModA.Bar\n\nextension BA {\n    public func barSecret() {}\n}\n"
        let elements = ElementOptions(
            havingAccessLevel: [.public, .open], showExtensions: .merged, exclude: ["ModA.*", "BA"]
        )
        let graph = try graph([("ModA", modA), ("ModB", modB)], Configuration(elements: elements, format: .svg))
        #expect(graph.owner(of: "visible") != nil)
        #expect(graph.owner(of: "secret") == nil)
        #expect(graph.owner(of: "barSecret") == nil)
    }

    @Test("a conformance written with and without the module is drawn once")
    func repeatedConformanceDrawnOnce() throws {
        let modA = "public protocol P {}\n\npublic struct Foo: P {\n    public init() {}\n}\n"
        let modB = "import ModA\n\nextension ModA.Foo: ModA.P {}\n"
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        for format in [DiagramFormat.plantuml, .mermaid] {
            let edges = ClassDiagramIds.lines(
                of: try text(files, Configuration(elements: Self.merged, format: format)), containing: "<|.."
            )
            #expect(edges == ["P <|.. Foo : conforms to"])
        }
    }

    /// `Settings.*` names the types nested in `Settings`; `Contract` is only an alias there of
    /// the top-level `Configurable`, so the edge to it stays.
    @Test("a pattern for a type's members does not hide an edge through its nested alias")
    func nestedAliasNotExcludedByItsName() throws {
        let source = """
            protocol Configurable {}

            enum Settings {
                typealias Contract = Configurable
                struct Theme: Contract {}
            }
            """
        let excluded = RelationshipOptions(realize: Relationship(label: "conforms to", exclude: ["Settings.*"]))
        let edges = ClassDiagramIds.lines(
            of: try text([(nil, source)], Configuration(relationships: excluded)), containing: "<|"
        )
        #expect(edges == ["Configurable <|.. Settings.Theme : conforms to"])
    }

    /// Lib's `typealias Describable = CustomStringConvertible`, extended first as
    /// `Lib.Describable` and then as `CustomStringConvertible`: merged, the two are one box,
    /// recorded under the qualified spelling, and an edge written with either spelling, or from
    /// a type nested in an extension of a type outside the diagram, ends on it, as it does with
    /// the alias written bare.
    @Test("an edge to an outside type ends on the box its extensions merge into through a module's alias")
    func outsideTypeEndsOnModuleAliasHost() throws {
        let lib = "public typealias Describable = CustomStringConvertible\n"
        let app = """
            import Foundation
            import Lib

            extension Lib.Describable { func viaModule() {} }
            extension CustomStringConvertible { func direct() {} }
            struct T: CustomStringConvertible { var description: String { "" } }
            struct S: Describable { var description: String { "" } }
            extension Date { struct Stamp: CustomStringConvertible { var description: String { "" } } }
            """
        let files: [(module: String?, source: String)] = [("Lib", lib), ("App", app)]
        let svg = try graph(files, Configuration(elements: Self.merged, format: .svg))
        let host = try #require(svg.owner(of: "direct"))
        #expect(svg.owner(of: "viaModule") == host)
        for child in ["T", "S", "Date.Stamp"] {
            #expect(svg.edgeEnds.contains("\(child) -> \(host)"))
        }
        let edges = ClassDiagramIds.lines(of: try text(files, Configuration(elements: Self.merged)), containing: "<|--")
        #expect(edges == ["T", "S", "Date.Stamp"].map { "\(host) <|-- \($0) : inherits" })
    }
}
