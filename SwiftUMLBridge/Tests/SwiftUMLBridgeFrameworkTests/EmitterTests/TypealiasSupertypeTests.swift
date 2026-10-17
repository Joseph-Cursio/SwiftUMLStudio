import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// After `typealias Q = Proto`, `struct S: Q {}` conforms to `Proto`. PlantUML, Mermaid and
/// Nomnoml wrote the edge to an undeclared `Q`, labelled `inherits`, and `deps --types` drew it
/// to a `Q` node, while SVG already followed the alias (#125). Each now reads the supertype as
/// the direct spelling would, so the script is the one `struct S: Proto {}` gives.
@Suite("Supertypes written through a typealias")
struct TypealiasSupertypeTests {
    static let formats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]

    private func script(_ source: String, _ format: DiagramFormat, relationships: RelationshipOptions? = nil,
                        extensions: ExtensionVisualization = .all) -> String {
        var configuration = Configuration(elements: ElementOptions(showExtensions: extensions), format: format)
        if let relationships { configuration.relationships = relationships }
        return ClassDiagramGenerator().generateScript(for: source, with: configuration).text
    }

    /// The supertype edges of a PlantUML, Mermaid or Nomnoml script.
    private func edges(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { $0.contains("<|--") || $0.contains("-:>") }
    }

    /// A fresh directory holding `files`, each path to its contents; removed by the caller.
    private func directory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - Class diagrams

    @Test("a conformance through a typealias is drawn as the direct conformance is", arguments: formats)
    func conformanceThroughAlias(format: DiagramFormat) {
        let viaAlias = script("protocol Proto {}\ntypealias Q = Proto\nstruct S: Q {}", format)
        #expect(viaAlias == script("protocol Proto {}\nstruct S: Proto {}", format))
        #expect(!viaAlias.contains("Q"), "\(viaAlias)")
    }

    @Test("a superclass through a typealias is drawn as the direct superclass is", arguments: formats)
    func superclassThroughAlias(format: DiagramFormat) {
        let viaAlias = script("class Base {}\ntypealias BaseAlias = Base\nclass Sub: BaseAlias {}", format)
        #expect(viaAlias == script("class Base {}\nclass Sub: Base {}", format))
    }

    @Test("a nested alias, a chain and an alias of a bound generic are followed", arguments: formats)
    func moreAliasShapes(format: DiagramFormat) {
        let nested = "protocol Proto {}\nenum Names { typealias Q = Proto }\nstruct S: Names.Q {}"
        #expect(script(nested, format) == script("protocol Proto {}\nenum Names {}\nstruct S: Proto {}", format))
        let chain = "protocol Proto {}\ntypealias A1 = A2\ntypealias A2 = Proto\nstruct S: A1 {}"
        #expect(script(chain, format) == script("protocol Proto {}\nstruct S: Proto {}", format))
        // `class Sub: Box<Int>` also gives `Sub` itself the generics `<Int>`, so only the edges compare.
        let bound = "class Box<T> {}\ntypealias IntBox = Box<Int>\nclass Sub: IntBox {}"
        #expect(edges(script(bound, format)) == edges(script("class Box<T> {}\nclass Sub: Box<Int> {}", format)))
        #expect(edges(script(bound, format)).count == 1)
    }

    /// `extension S: Q {}` merged into `S` carries `Q`, looked up from the extension (#76).
    @Test("a conformance a merged extension carries through a typealias is drawn to the aliased type",
          arguments: formats)
    func carriedConformanceThroughAlias(format: DiagramFormat) {
        let viaAlias = script(
            "protocol Proto {}\ntypealias Q = Proto\nstruct S {}\nextension S: Q {}", format, extensions: .merged
        )
        let direct = script("protocol Proto {}\nstruct S {}\nextension S: Proto {}", format, extensions: .merged)
        #expect(viaAlias == direct)
    }

    @Test("excluding either the alias or the aliased type hides the edge", arguments: ["Q", "Proto"])
    func excludeEitherName(pattern: String) {
        let relationships = RelationshipOptions(realize: Relationship(exclude: [pattern]))
        let source = "protocol Proto {}\ntypealias Q = Proto\nstruct S: Q {}"
        for format in Self.formats {
            let text = script(source, format, relationships: relationships)
            #expect(text == script("protocol Proto {}\nstruct S {}", format), "\(format): \(text)")
        }
        let configuration = Configuration(relationships: relationships, format: .svg)
        let graph = ClassDiagramGenerator().generateScript(for: source, with: configuration).layoutGraph
        #expect(graph?.edges.isEmpty == true)
    }

    /// A `fileprivate` alias names its type only in its own file, so `S` in another file
    /// conforms to whatever else `Q` means there: here an undeclared `Q`, as written.
    @Test("a fileprivate alias in another file is not followed")
    func fileprivateAliasInAnotherFile() throws {
        let root = try directory([
            "A.swift": "protocol Proto {}\nfileprivate typealias Q = Proto\nstruct Here: Q {}",
            "B.swift": "struct There: Q {}"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let text = ClassDiagramGenerator().generateScript(
            for: [root.path], with: Configuration(format: .plantuml)
        ).text
        #expect(text.contains("Proto <|.. Here : conforms to"), "\(text)")
        #expect(text.contains("Q <|-- There : inherits"), "\(text)")
    }

    // MARK: - deps --types

    @Test("deps --types draws an edge through a typealias, in another file, to the aliased type")
    func depsThroughAlias() throws {
        let root = try directory([
            "Proto.swift": "protocol Proto {}\nclass Base {}\ntypealias Alias2 = Proto\ntypealias BaseAlias = Base",
            "User.swift": "struct User: Alias2 {}\nclass Sub: BaseAlias {}"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let edges = DependencyGraphGenerator().extractEdges(for: [root.path], mode: .types)
            .map { "\($0.from) -> \($0.to)" }
        #expect(edges.sorted() == ["Sub -> Base", "User -> Proto"])
    }

    @Test("deps --types drops an edge whose aliased type is excluded")
    func depsExcludeAliasedType() throws {
        let root = try directory(["A.swift": "protocol Proto {}\ntypealias Q = Proto\nstruct S: Q {}"])
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = Configuration(elements: ElementOptions(exclude: ["Proto"]))
        #expect(DependencyGraphGenerator().extractEdges(for: [root.path], mode: .types, with: configuration).isEmpty)
    }

    /// Across targets an alias below `package` is invisible, so `Networking` sees only Core's
    /// public alias.
    @Test("deps --types --package follows a public alias across targets, not an internal one")
    func depsPackageAcrossTargets() throws {
        let root = try directory([
            "Sources/Core/Proto.swift": """
                public protocol Proto {}
                public typealias PublicQ = Proto
                typealias InternalQ = Proto
                """,
            "Sources/Networking/Client.swift": """
                public struct ViaPublic: PublicQ {}
                public struct ViaInternal: InternalQ {}
                """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let package = SPMPackageDescription(name: "Pkg", targets: [
            SPMTargetDescription(name: "Core", kind: .library, path: "Sources/Core",
                                 sources: ["Proto.swift"], dependencies: []),
            SPMTargetDescription(name: "Networking", kind: .library, path: "Sources/Networking",
                                 sources: ["Client.swift"], dependencies: ["Core"])
        ])
        let text = DependencyGraphGenerator().generateScript(
            forPackage: package, packageRoot: root, mode: .types, with: Configuration(format: .plantuml)
        ).text
        let edges = text.split(separator: "\n").filter { $0.contains("-->") }.map(String.init)
        #expect(edges == ["ViaPublic --> Proto : conforms", "ViaInternal --> InternalQ : conforms"])
    }
}
