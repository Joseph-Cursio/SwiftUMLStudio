import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Where a module qualifier can be read (#124): only in a file that imports the module or is in
/// it, and only when no type of that name the file can see is in the way. And where an edge to a
/// hidden type ends once `--merge-extensions` has merged its extensions, however they spell it.
@Suite("Module qualifiers, imports and hidden types")
struct ModuleQualifiedScopeTests {

    private static let merged = ElementOptions(showExtensions: .merged)

    private func graph(
        _ files: [(module: String?, source: String)], _ elements: ElementOptions = Self.merged
    ) throws -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: try moduleQualifiedItems(files), configuration: Configuration(elements: elements, format: .svg)
        )
    }

    // MARK: - Imports

    /// App imports Foundation, not the target Calendar, so `Calendar.Component` is Foundation's
    /// `Calendar.Component`, which the diagram does not declare.
    @Test("a target the file does not import is not read as a module")
    func unimportedTargetIsNoModule() throws {
        let calendar = "public struct Component {\n    public init() {}\n}"
        let app = """
            import Foundation

            extension Calendar.Component {
                func fromApp() {}
            }
            """
        let graph = try graph([("Calendar", calendar), ("App", app)])
        #expect(graph.owner(of: "fromApp") == "Calendar.Component")
    }

    /// App imports Core, so Swift reads `Analytics` as Core's type, whatever the type holds, and
    /// `Analytics.Event` as a member of it — here one added in an extension, one inherited from
    /// a superclass, or one reached through a typealias. It is not module Analytics's `Event`.
    @Test("a type in an imported module named like the qualifier keeps it a type", arguments: [
        "public enum Analytics {}\n\nextension Analytics {\n    public struct Event {}\n}",
        "open class Base {\n    public struct Event {}\n}\n\nopen class Analytics: Base {}",
        "public enum Events {\n    public struct Event {}\n}\n\npublic typealias Analytics = Events"
    ])
    func importedTypeShadows(core: String) throws {
        let analytics = "public struct Event {\n    public init() {}\n}"
        let app = """
            import Analytics
            import Core

            extension Analytics.Event {
                func track() {}
            }
            """
        let graph = try graph(
            [("Analytics", analytics), ("Core", core), ("App", app)],
            ElementOptions(showNestedTypes: false, showExtensions: .merged)
        )
        #expect(graph.owner(of: "track") == "Analytics.Event")
    }

    /// App imports Foundation and the target Calendar, so `Calendar` is Foundation's type, which
    /// the diagram does not declare: App adds `Holiday` to it, `Calendar.Holiday` is that, and
    /// inside `extension Calendar` the name `Event` is App's own, not the target's.
    @Test("a type outside the diagram named like an imported target is still read first")
    func outsideTypeBeforeImportedTarget() throws {
        let calendar = "public struct Holiday {\n    public init() {}\n}\n\npublic protocol Event {}\n"
        let app = """
            import Foundation
            import Calendar

            protocol Event {}

            extension Calendar {
                struct Holiday: Event {}
            }

            extension Calendar.Holiday {
                func fromApp() {}
            }
            """
        let graph = try graph([("Calendar", calendar), ("App", app)])
        #expect(graph.owner(of: "fromApp") == "Calendar.Holiday")
        #expect(graph.edgeEnds.contains("Calendar.Holiday -> Event_1"))
    }

    @Test("an import inside #if counts")
    func importInIfConfig() throws {
        let modA = "public struct Foo {\n    public init() {}\n}"
        let modB = """
            #if canImport(ModA)
            import ModA
            #endif

            extension ModA.Foo {
                func fromB() {}
            }
            """
        let graph = try graph([("ModA", modA), ("ModB", modB)])
        #expect(graph.owner(of: "fromB") == "Foo")
    }

    // MARK: - Hidden types

    private static let internalOnly = ElementOptions(havingAccessLevel: [.internal])
    private static let internalMerged = ElementOptions(havingAccessLevel: [.internal], showExtensions: .merged)

    /// ModA's public `P` is hidden. Its extensions merge into ModA's `extension P`, and both
    /// supertype edges end on that box, however each spells `P`.
    @Test("an edge to a hidden type ends on the box its extensions merged into")
    func edgesEndOnMergeHost() throws {
        let modA = "public protocol P {}\n\nextension P {\n    public func fromA() {}\n}\n"
        let modB = """
            import ModA

            extension ModA.P {
                func fromB() {}
            }

            struct S: ModA.P {}
            struct T: P {}
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        let graph = try graph(files, Self.internalMerged)
        #expect(graph.owner(of: "fromB") == "P")
        #expect(graph.edgeEnds.sorted() == ["S -> P", "T -> P"])
        // The text formats end `S: ModA.P` on the merged box too, as they end `T: P`.
        let text = DiagramScript(
            items: try moduleQualifiedItems(files), configuration: Configuration(elements: Self.internalMerged)
        ).text
        let edges = ClassDiagramIds.lines(of: text, containing: "<|").sorted()
        #expect(edges.count == 2)
        #expect(edges.allSatisfy { $0.hasPrefix("P <|") })
        #expect(edges.map { $0.replacingOccurrences(of: " S ", with: " T ") }.allSatisfy { $0 == edges[1] })
    }

    /// The first extension of the hidden `Foo` spells it through a typealias and its module, so
    /// that box is the merge host, and the nested `Kid` hangs off it.
    @Test("a nested type of a hidden type hangs off the merge host, however the host spells it")
    func nestedTypeOnAliasSpelledHost() throws {
        let modA = "public struct Foo {\n    struct Kid {}\n}\n\npublic typealias Thing = Foo\n"
        let modB = """
            import ModA

            extension ModA.Thing {
                func viaAlias() {}
            }

            extension ModA.Foo {
                func direct() {}
            }
            """
        let graph = try graph([("ModA", modA), ("ModB", modB)], Self.internalMerged)
        #expect(graph.owner(of: "direct") == "ModA.Thing")
        #expect(graph.edgeEnds == ["ModA.Thing -> Foo.Kid"])
    }

    /// `elements.exclude` names `Outer.Inner`, which hides the type and ModA's `extension Outer.Inner`
    /// but not ModB's `extension ModA.Outer.Inner`. The hidden extension's members must not come
    /// back by merging into the one that is drawn.
    @Test("an excluded extension does not merge into a host spelled through a module")
    func excludedExtensionStaysHidden() throws {
        let modA = """
            public enum Outer {
                public struct Inner {}
            }

            extension Outer.Inner {
                func secretA() {}
            }
            """
        let modB = "import ModA\n\nextension ModA.Outer.Inner {\n    func fromB() {}\n}\n"
        let excluding = ElementOptions(showExtensions: .merged, exclude: ["Outer.Inner"])
        let graph = try graph([("ModA", modA), ("ModB", modB)], excluding)
        #expect(graph.owner(of: "fromB") == "ModA.Outer.Inner")
        #expect(graph.owner(of: "secretA") == nil)
    }

    /// The alias is declared in `extension ModA.Foo`, so it is `Foo.Alias` too, as it is once
    /// merged into `Foo`, and `extension Foo.Alias` extends `Bar` with and without merging.
    @Test("a typealias declared in a qualified extension is also known by the type's own name")
    func aliasInQualifiedExtension() throws {
        let modA = "public struct Foo {\n    public init() {}\n}\n\npublic struct Bar {\n    public init() {}\n}\n"
        let modB = """
            import ModA

            extension ModA.Foo {
                typealias Alias = Bar
            }

            extension Foo.Alias {
                func viaAlias() {}
            }
            """
        let files: [(module: String?, source: String)] = [("ModA", modA), ("ModB", modB)]
        #expect(try graph(files).owner(of: "viaAlias") == "Bar")
        let text = DiagramScript(items: try moduleQualifiedItems(files), configuration: Configuration()).text
        #expect(ClassDiagramIds.lines(of: text, containing: " : ext").contains("Bar <.. Foo.Alias : ext"))
    }

    /// `S: Alias` ends where the text formats end it, on the box named `Q`, before the box of
    /// `extension App.Q`, which spells the type through its module.
    @Test("a stand-in under the type's own name comes before one spelled through its module")
    func ownNameBeforeQualified() throws {
        let app = """
            protocol Q {}
            typealias Alias = Q

            extension App.Q {
                public func viaModule() {}
            }

            extension Q {
                public func plain() {}
            }

            public struct S: Alias {}
            """
        let publicOnly = ElementOptions(havingAccessLevel: [.public, .open])
        let graph = try graph([("App", app)], publicOnly)
        let plainBox = try #require(graph.owner(of: "plain"))
        #expect(graph.edgeEnds == ["S -> \(plainBox)"])
        let text = DiagramScript(
            items: try moduleQualifiedItems([("App", app)]),
            configuration: Configuration(elements: publicOnly, format: .plantuml)
        ).text
        #expect(ClassDiagramIds.lines(of: text, containing: "<|--") == ["Q <|-- S : inherits"])
    }
}
