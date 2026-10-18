import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// In package mode every declaration carries its target as its module, so `extension ModA.Foo`
/// written in ModB extends ModA's `Foo`, and `extension ModA.Foo.Inner` its nested `Foo.Inner`: the
/// module name is a qualifier, not part of the type's name. `TypeLookup` used to look the
/// extension up under `ModA.Foo`, which no type is named, so it was never merged into its type and
/// got no `ext` edge (#124).
@Suite("Module-qualified extensions find the type they extend")
struct ModuleQualifiedExtensionTests {
    private static let modA = """
        public struct Foo {
            public init() {}
            public struct Inner {}
        }
        """

    private static let modB = """
        import ModA

        struct Foo {}

        extension ModA.Foo {
            func fromB() {}
        }

        extension ModA.Foo.Inner {
            func innerFromB() {}
        }

        extension Foo {
            func localB() {}
        }
        """

    /// ModB, with a type nested in each extension instead of a method.
    private static let nestedModB = """
        import ModA

        struct Foo {}

        extension ModA.Foo {
            struct Nested {}
        }

        extension Foo {
            struct LocalNested {}
        }
        """

    private static let merged = ElementOptions(showExtensions: .merged)

    /// Each module's file parsed as `generateScript(forPackage:)` parses it, in the order given;
    /// `module` is `nil` for a directory-mode parse.
    private func items(_ files: [(module: String?, source: String)]) throws -> [SyntaxStructure] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var items: [SyntaxStructure] = []
        for (index, file) in files.enumerated() {
            let url = directory.appendingPathComponent("\(file.module ?? "File")\(index).swift")
            try file.source.write(to: url, atomically: true, encoding: .utf8)
            items += try #require(SyntaxStructure.create(from: url, module: file.module)?.substructure)
        }
        return items
    }

    private func packageItems(modB: String = Self.modB) throws -> [SyntaxStructure] {
        try items([("ModA", Self.modA), ("ModB", modB)])
    }

    private func lines(
        _ items: [SyntaxStructure], _ configuration: Configuration, containing marker: String
    ) -> [String] {
        ClassDiagramIds.lines(of: DiagramScript(items: items, configuration: configuration).text, containing: marker)
    }

    private func mergedGraph(_ items: [SyntaxStructure]) -> LayoutGraph {
        LayoutGraphBuilder.buildClassDiagram(
            from: items, configuration: Configuration(elements: Self.merged, format: .svg)
        )
    }

    /// The id of the merged node that lists `member`.
    private func owner(of member: String, in graph: LayoutGraph) -> String? {
        graph.nodes.first { $0.compartments.flatMap(\.items).contains { $0.contains(member) } }?.id
    }

    // MARK: - The issue's reproduction

    @Test("a qualified extension gets an ext edge to the type it extends", arguments: [
        (DiagramFormat.plantuml, "<.."), (.mermaid, "<..")
    ])
    func qualifiedExtensionEdge(format: DiagramFormat, arrow: String) throws {
        let edges = lines(try packageItems(), Configuration(format: format), containing: arrow)
        #expect(edges == ["Foo <.. ModA.Foo : ext", "Foo.Inner <.. ModA.Foo.Inner : ext", "Foo0 <.. Foo1 : ext"])
    }

    @Test("Nomnoml draws the same ext edges")
    func qualifiedExtensionEdgeNomnoml() throws {
        let edges = lines(try packageItems(), Configuration(format: .nomnoml), containing: "ext")
            .filter { $0.hasPrefix("[") && $0.contains("<") == false }
        #expect(edges == ["[ModA.Foo] --> ext [Foo]", "[ModA.Foo.Inner] --> ext [Foo.Inner]", "[Foo1] --> ext [Foo0]"])
    }

    @Test("--merge-extensions merges a qualified extension into the type it extends")
    func qualifiedExtensionMerges() throws {
        let graph = mergedGraph(try packageItems())
        #expect(graph.nodeIds == ["Foo", "Foo.Inner", "Foo_1"])
        #expect(owner(of: "fromB", in: graph) == "Foo")
        #expect(owner(of: "innerFromB", in: graph) == "Foo.Inner")
        #expect(owner(of: "localB", in: graph) == "Foo_1")
    }

    @Test("a type nested in a qualified extension hangs off the type it extends")
    func nestedInQualifiedExtension() throws {
        let items = try packageItems(modB: Self.nestedModB)
        let svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(svg.edgeEnds.contains("Foo -> ModA.Foo.Nested"))
        #expect(svg.edgeEnds.contains("Foo_1 -> Foo.LocalNested"))

        let nesting = lines(items, Configuration(elements: Self.merged, format: .plantuml), containing: "+--")
        #expect(nesting.contains("Foo +-- ModA.Foo.Nested"))
        #expect(nesting.contains("Foo0 +-- Foo.LocalNested"))
    }

    /// With ModB's file first, ModB's `Foo` takes the id `Foo` and ModA's `Foo0`; the qualified
    /// extensions still end on ModA's types.
    @Test("the edges do not depend on which module's file is parsed first")
    func otherOrder() throws {
        let items = try items([("ModB", Self.modB), ("ModA", Self.modA)])
        let edges = lines(items, Configuration(format: .plantuml), containing: "<..")
        #expect(edges == ["Foo0 <.. ModA.Foo : ext", "Foo.Inner <.. ModA.Foo.Inner : ext", "Foo <.. Foo1 : ext"])
        let graph = mergedGraph(items)
        #expect(owner(of: "fromB", in: graph) == "Foo_1")
        #expect(owner(of: "localB", in: graph) == "Foo")
    }

    // MARK: - What the qualifier is read as

    /// In Swift a type shadows a module of its name, so `Networking.Request` in App means the
    /// nested type even though module Networking also declares a top-level `Request`.
    @Test("a type named like a module is tried first")
    func fullNameFirst() throws {
        let networking = """
            public enum Networking {
                public struct Request {}
            }
            public struct Request {}
            """
        let app = """
            import Networking

            extension Networking.Request {
                func fromApp() {}
            }
            """
        let graph = mergedGraph(try items([("Networking", networking), ("App", app)]))
        #expect(owner(of: "fromApp", in: graph) == "Networking.Request")
    }

    /// Inside App's own `enum Networking`, Swift looks `Endpoint` up as a member of that enum,
    /// then in App, so it means App's `Endpoint`. The enum shadows the module Networking, so
    /// `Networking.Endpoint` must not be read as that module's `Endpoint` on the way.
    @Test("a visible type named like a module keeps the qualifier a type")
    func typeShadowsModule() throws {
        let networking = "public protocol Endpoint {}"
        let app = """
            import Networking

            protocol Endpoint {}

            enum Networking {
                struct Request: Endpoint {}
            }
            """
        let items = try items([("Networking", networking), ("App", app)])
        let svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(svg.edgeEnds.contains("Networking.Request -> Endpoint_1"))
    }

    @Test("a module may qualify its own types")
    func ownModuleQualifier() throws {
        let modB = """
            import ModA

            struct Foo {}

            extension ModB.Foo {
                func own() {}
            }
            """
        let graph = mergedGraph(try packageItems(modB: modB))
        #expect(owner(of: "own", in: graph) == "Foo_1")
    }

    /// Swift code names a target by its C99 name: `my-lib` is `my_lib`, `2D` is `_2D`.
    @Test("a target is matched by the module name Swift code writes", arguments: [
        ("my-lib", "my_lib"), ("2D", "_2D"), ("Plain", "Plain")
    ])
    func c99ModuleName(target: String, qualifier: String) throws {
        let app = """
            extension \(qualifier).Foo {
                func viaModuleName() {}
            }
            """
        let graph = mergedGraph(try items([(target, Self.modA), ("App", app)]))
        #expect(owner(of: "viaModuleName", in: graph) == "Foo")
    }

    @Test("a qualifier that names no module in the diagram is left as written")
    func unknownModule() throws {
        let app = """
            extension String {
                func plain() {}
            }

            extension Swift.String {
                func qualified() {}
            }
            """
        let graph = mergedGraph(try items([("App", app)]))
        #expect(graph.nodeIds == ["String", "Swift.String"])
    }

    @Test("without modules, a qualified extension is left as written")
    func directoryMode() throws {
        let graph = mergedGraph(try items([(nil, Self.modA), (nil, Self.modB)]))
        #expect(owner(of: "fromB", in: graph) == "ModA.Foo")
        #expect(owner(of: "innerFromB", in: graph) == "ModA.Foo.Inner")
    }

    // MARK: - What the qualified name can reach

    @Test("a module's internal type is not reached from another module")
    func internalTypeIsNotVisible() throws {
        let modA = "struct Hidden {}"
        let modB = """
            import ModA

            extension ModA.Hidden {
                func fromB() {}
            }
            """
        let graph = mergedGraph(try items([("ModA", modA), ("ModB", modB)]))
        #expect(owner(of: "fromB", in: graph) == "ModA.Hidden")
    }

    @Test("a qualified typealias means the type it aliases")
    func qualifiedTypealias() throws {
        let modA = Self.modA + "\npublic typealias Thing = Foo\n"
        let modB = """
            import ModA

            extension ModA.Thing {
                func viaAlias() {}
            }
            """
        let graph = mergedGraph(try items([("ModA", modA), ("ModB", modB)]))
        #expect(owner(of: "viaAlias", in: graph) == "Foo")
    }

    /// Only `internal` declarations are drawn, so ModA's `public` `Foo` is hidden while its
    /// internal `Inner` and ModB's extension (extensions pass the access filter) are drawn. The
    /// qualified extension stands in for `Foo`, as `extension Foo` would in ModA (#74, #153).
    @Test("a qualified extension stands in for the hidden type it extends")
    func standInForHiddenType() throws {
        let modA = """
            public struct Foo {
                struct Inner {}
            }
            """
        let modB = """
            import ModA

            extension ModA.Foo {
                func fromB() {}
            }
            """
        let items = try items([("ModA", modA), ("ModB", modB)])
        let internalOnly = ElementOptions(havingAccessLevel: [.internal])
        let svg = LayoutGraphBuilder.buildClassDiagram(
            from: items, configuration: Configuration(elements: internalOnly, format: .svg)
        )
        #expect(svg.edgeEnds == ["ModA.Foo -> Foo.Inner"])
        #expect(lines(items, Configuration(elements: internalOnly, format: .plantuml), containing: "+--")
            == ["ModA.Foo +-- Foo.Inner"])
    }

    @Test("a qualified supertype in a qualified extension reaches its protocol in SVG")
    func qualifiedSupertypeSVG() throws {
        let modA = Self.modA + "\npublic protocol Q {}\n"
        let modB = """
            import ModA

            extension ModA.Foo: ModA.Q {}
            """
        let items = try items([("ModA", modA), ("ModB", modB)])
        let svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
        #expect(svg.edgeEnds.contains("ModA.Foo -> Q"))
    }
}
