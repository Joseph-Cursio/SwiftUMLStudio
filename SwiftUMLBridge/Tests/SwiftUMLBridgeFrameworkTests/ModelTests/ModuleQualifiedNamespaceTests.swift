import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Which namespaces a file sees when it reads a module qualifier (#124): a type named like a
/// target keeps `Analytics.Event` a type only where Swift shows it to the file, through the
/// file's own module, its imports, scoped or not, or a module re-exported to it.
@Suite("Module qualifiers and the namespaces a file sees")
struct ModuleQualifiedNamespaceTests {

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

    /// Core's `enum Analytics` declares an `Event` too, but a file that does not import Core does
    /// not see that namespace, so there `Analytics.Event` is still the module Analytics's
    /// `Event`, in App and in Analytics itself. Importing Core makes the namespace a type the file
    /// sees, which keeps the qualifier a type, as Swift reads it.
    /// A scoped import makes only the declaration it names visible: `import struct Core.Thing`
    /// leaves the namespace unseen, and `import enum Core.Analytics` makes it seen.
    @Test("a namespace in a module the file does not import does not keep the qualifier a type", arguments: [
        ("App", "import Analytics\n", "Event", "Event <.. Analytics.Event0 : ext"),
        ("Analytics", "", "Event", "Event <.. Analytics.Event0 : ext"),
        ("App", "import Analytics\nimport Core\n", "Analytics.Event", "Analytics.Event <.. Analytics.Event0 : ext"),
        ("App", "import Analytics\nimport struct Core.Thing\n", "Event", "Event <.. Analytics.Event0 : ext"),
        (
            "App", "import Analytics\nimport enum Core.Analytics\n", "Analytics.Event",
            "Analytics.Event <.. Analytics.Event0 : ext"
        )
    ])
    func unimportedNamespaceDoesNotShadow(writer: String, imports: String, owner: String, extEdge: String) throws {
        let analytics = "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public struct Event {}\n}\npublic struct Thing {}"
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
    /// or of a module App imports, shows Core to that file alone, and a scoped re-export,
    /// `@_exported import struct Core.Thing`, shows only `Thing`.
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
         "Event", "Event <.. Analytics.Event0 : ext"),
        ("@_exported import struct Core.Thing\n", [], "import Analytics\n",
         "Event", "Event <.. Analytics.Event0 : ext")
    ])
    func reexportedNamespaceShadows(
        analyticsImports: String, others: [(module: String?, source: String)], appImports: String,
        owner: String, extEdge: String
    ) throws {
        let analytics = analyticsImports + "public struct Event {\n    public init() {}\n}"
        let core = "public enum Analytics {\n    public struct Event {}\n}\npublic struct Thing {}"
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
}
