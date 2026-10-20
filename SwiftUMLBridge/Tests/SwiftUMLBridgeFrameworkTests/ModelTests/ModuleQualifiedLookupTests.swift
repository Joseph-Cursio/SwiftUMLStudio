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

    /// Core's `enum Networking` gets a `Request` in an extension, and App imports Core and the
    /// module Networking, so in Swift `Networking.Request` is Core's nested type, not the module's.
    @Test("a full name that means a type is not read through a module")
    func fullNameBeforeModule() throws {
        let networking = "public struct Request {\n    public init() {}\n}"
        let core = "public enum Networking {}\n\nextension Networking {\n    public struct Request {}\n}"
        let app = """
            import Core
            import Networking

            extension Networking.Request {
                func fromApp() {}
            }
            """
        let graph = try graph([("Networking", networking), ("Core", core), ("App", app)])
        #expect(graph.owner(of: "fromApp") == "Networking.Request")
    }

    /// Module Foo's `class Foo` inherits `Rest` from `Base`, so `Foo.Rest` is `Base.Rest`, which the
    /// lookup does not follow; the module's own top-level `Rest` is not what it means.
    @Test("a type named like the module it is in keeps the qualifier a type")
    func namedModuleTypeShadows() throws {
        let foo = """
            open class Base {
                public struct Rest {}
            }

            public final class Foo: Base {}

            public struct Rest {}
            """
        let app = "import Foo\n\nextension Foo.Rest {\n    func fromApp() {}\n}\n"
        let graph = try graph([("Foo", foo), ("App", app)])
        #expect(graph.owner(of: "fromApp") == "Foo.Rest")
    }

    /// With nested types not drawn, Core's `Analytics.Event` is a member of `enum Analytics`
    /// only; App imports Core, so Swift reads `Analytics.Event` as that member.
    @Test("a type in a third module with a member of the next name keeps the qualifier a type")
    func thirdModuleTypeWithMemberShadows() throws {
        let analytics = "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public struct Event {}\n}"
        let app = """
            import Analytics
            import Core

            extension Analytics.Event {
                func track() {}
            }
            """
        let unnested = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        let graph = try graph(
            [("Analytics", analytics), ("Core", core), ("App", app)], Configuration(elements: unnested, format: .svg)
        )
        #expect(graph.owner(of: "track") == "Analytics.Event")
    }

    /// Core's `enum Analytics` declares an `Event` too, but a file that does not import Core does
    /// not see that namespace, so there `Analytics.Event` is still the module Analytics's
    /// `Event`, in App and in Analytics itself. Importing Core makes the namespace a type the file
    /// sees, which keeps the qualifier a type, as Swift reads it.
    @Test("a namespace in a module the file does not import does not keep the qualifier a type", arguments: [
        ("App", "import Analytics\n", "Event", "Event <.. Analytics.Event0 : ext"),
        ("Analytics", "", "Event", "Event <.. Analytics.Event0 : ext"),
        ("App", "import Analytics\nimport Core\n", "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext")
    ])
    func unimportedNamespaceDoesNotShadow(writer: String, imports: String, owner: String, extEdge: String) throws {
        let analytics = "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public struct Event {}\n}"
        let written = imports + "\nextension Analytics.Event {\n    func track() {}\n}\n"
        let files: [(module: String?, source: String)] = [("Analytics", analytics), ("Core", core), (writer, written)]
        #expect(try graph(files).owner(of: "track") == owner)
        #expect(try lines(files, Configuration(format: .plantuml), containing: ": ext") == [extEdge])
    }

    /// An `@_exported import Core` shows Core's `enum Analytics` to every file of the module that
    /// writes it and to every file importing that module, down a chain of re-exports, so there
    /// the namespace keeps `Analytics.Event` a type, as Swift reads it: in App importing Analytics,
    /// which re-exports Core; beside an `Exports.swift` of App's own; and through an Umbrella App
    /// imports, directly or through one that re-exports it in turn. A module re-exported so is
    /// one the file can name too: through an Umbrella that re-exports Analytics,
    /// `Analytics.Event` is the target's `Event`. A plain `import Core` in another file, of App
    /// or of a module App imports, shows Core to that file alone.
    @Test("a re-exported namespace keeps the qualifier a type", arguments: [
        ("@_exported import Core\n", [] as [(module: String?, source: String)], "import Analytics\n",
         "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext"),
        ("", [("App", "@_exported import Core\n")], "import Analytics\n",
         "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext"),
        ("", [("Umbrella", "@_exported import Core\n")], "import Analytics\nimport Umbrella\n",
         "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext"),
        ("", [("Bridge", "@_exported import Core\n"), ("Umbrella", "@_exported import Bridge\n")],
         "import Analytics\nimport Umbrella\n", "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext"),
        ("", [("Umbrella", "@_exported import Analytics\n")], "import Umbrella\n",
         "Event", "Event <.. Analytics.Event0 : ext"),
        ("", [("App", "import Core\n")], "import Analytics\n", "Event", "Event <.. Analytics.Event0 : ext"),
        ("", [("Umbrella", "import Core\n")], "import Analytics\nimport Umbrella\n",
         "Event", "Event <.. Analytics.Event0 : ext")
    ])
    func reexportedNamespaceShadows(
        analyticsImports: String, others: [(module: String?, source: String)], appImports: String,
        owner: String, extEdge: String
    ) throws {
        let analytics = analyticsImports + "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public struct Event {}\n}"
        let written = appImports + "\nextension Analytics.Event {\n    func track() {}\n}\n"
        let files = [("Analytics", analytics), ("Core", core)] + others + [("App", written)]
        #expect(try graph(files).owner(of: "track") == owner)
        #expect(try lines(files, Configuration(format: .plantuml), containing: ": ext") == [extEdge])
    }

    /// A supertype is read as an extended type is: Core's `Analytics.Base`, re-exported.
    @Test("a re-exported namespace keeps a supertype's qualifier a type")
    func reexportedNamespaceKeepsSupertype() throws {
        let analytics = "@_exported import Core\nopen class Base {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    open class Base {\n        public init() {}\n    }\n}"
        let app = "import Analytics\n\nfinal class Sub: Analytics.Base {}\n"
        let files: [(module: String?, source: String)] = [("Analytics", analytics), ("Core", core), ("App", app)]
        #expect(try lines(files, Configuration(format: .plantuml), containing: ": inherits")
            == ["Analytics.Base <|-- Sub : inherits"])
    }

    /// In `extension Settings`, `Settings` is Models' type even beside a target named Settings,
    /// so `Section` is not looked for in that module: App's own `Section` is the one.
    @Test("a member is looked for through a module only in an extension named through one")
    func memberProbeIgnoresTargetNamedLikeType() throws {
        let models = "public struct Settings {\n    public init() {}\n}"
        let settings = "public protocol Section {}"
        let app = """
            import Models
            import Settings

            protocol Section {}

            extension Settings {
                struct General: Section {}
            }
            """
        let files: [(module: String?, source: String)] = [("Models", models), ("Settings", settings), ("App", app)]
        let edges = try graph(files, Configuration(format: .svg)).edgeEnds
        #expect(edges.contains("Settings.General -> Section_1"))
    }

    // MARK: - Stand-ins for a hidden type

    /// Only internal declarations are drawn, so ModA's public `Foo` is hidden while its internal
    /// `Inner` and both extensions are drawn. The stand-in is ModA's `extension Foo`, whichever
    /// file comes first: an extension that names the type as the edge does comes before one that
    /// names it through its module, so the box keeps the name the text formats' edges end on, and
    /// `--merge-extensions` merges the other into it.
    @Test("an extension spelled without the module stands in before one spelled through it", arguments: [
        ["ModA", "ModB"], ["ModB", "ModA"]
    ])
    func standInOrder(order: [String]) throws {
        let standIn = "Foo"
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

    /// Only public declarations are drawn, so the internal `Real` is hidden and `extension Alias`
    /// stands in for it under the name the edge is written with, as it did before #124.
    @Test("an extension spelled like the edge still stands in for a hidden type", arguments: [String?.none, "App"])
    func aliasSpelledStandIn(module: String?) throws {
        let app = """
            protocol Real {}
            typealias Alias = Real

            extension Alias {
                public func viaAlias() {}
            }

            public struct S: Alias {}
            """
        let publicOnly = ElementOptions(havingAccessLevel: [.public, .open])
        let graph = try graph([(module, app)], Configuration(elements: publicOnly, format: .svg))
        #expect(graph.edgeEnds == ["S -> Alias"])
    }
}
