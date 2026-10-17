import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// `deps --package` labels each node with the module that declares it (`--types`) or with its
/// target kind (`--modules`) in PlantUML, Mermaid and Nomnoml. The SVG document, and Studio's
/// native canvas, which draws the same `layoutGraph`, showed neither (#144).
@Suite("deps --package shows each node's module or target kind in SVG")
struct DepsPackageSVGModuleTests {
    /// `Core` declares `protocol Repo` and `struct UserRepo: Repo`; `App` declares
    /// `struct AppRepo: Repo, Sendable`. This is the package under *Reproduction*.
    static func script(_ mode: DepsMode, _ format: DiagramFormat) throws -> DepsScript {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deps-svg-module-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            ("Sources/Core/Repo.swift", "public protocol Repo {}\npublic struct UserRepo: Repo { public init() {} }\n"),
            ("Sources/App/main.swift", "import Core\nstruct AppRepo: Repo, Sendable {}\nprint(UserRepo())\n")
        ]
        for (path, source) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
        let description = SPMPackageDescription(name: "Demo", targets: [
            SPMTargetDescription(name: "Core", kind: .library, path: "Sources/Core",
                                 sources: ["Repo.swift"], dependencies: []),
            SPMTargetDescription(name: "App", kind: .executable, path: "Sources/App",
                                 sources: ["main.swift"], dependencies: ["Core"])
        ])
        return DependencyGraphGenerator().generateScript(
            forPackage: description, packageRoot: root, mode: mode, with: Configuration(format: format))
    }

    /// What the text formats label each node with (see the tests below).
    static func expected(_ mode: DepsMode) -> [(node: String, label: String)] {
        mode == .types
            ? [("AppRepo", "App"), ("Repo", "Core"), ("UserRepo", "Core")]
            : [("App", "executable"), ("Core", "library")]
    }

    /// The content of each `<text>` element, e.g. `&#x00AB;class&#x00BB;` or `Repo`.
    static func svgTexts(_ svg: String) throws -> [String] {
        let regex = try Regex("<text[^>]*>([^<]*)</text>")
        return svg.matches(of: regex).compactMap { $0.output[1].substring.map(String.init) }
    }

    @Test("the SVG document shows each node's module or target kind", arguments: [DepsMode.types, .modules])
    func svgShowsModule(mode: DepsMode) throws {
        let texts = try Self.svgTexts(try Self.script(mode, .svg).text)
        for label in Set(Self.expected(mode).map(\.label)).sorted() {
            #expect(texts.contains { $0 == label || $0 == "&#x00AB;\(label)&#x00BB;" }, "\(label)")
        }
    }

    /// A type's target is its `module`, so the layout draws a box per target, as a package class
    /// diagram does. `Sendable`, declared in no target, sits outside them.
    @Test("in --types the layout graph Studio draws puts each type in its target's box")
    func layoutGraphCarriesModule() throws {
        let graph = try #require(try Self.script(.types, .svg).layoutGraph)
        for (name, module) in Self.expected(.types) {
            let node = try #require(graph.nodes.first { $0.label == name })
            #expect(node.module == module, "\(name)")
            #expect(node.stereotype == nil, "\(name)")
        }
        #expect(graph.nodes.first { $0.label == "Sendable" }?.module == nil)
        #expect(graph.clusters.map(\.label).sorted() == ["App", "Core"])
    }

    /// A target's kind is its stereotype. Setting it as `module` would draw a box labelled
    /// `library`, which reads as a module.
    @Test("in --modules the layout graph Studio draws stereotypes each target with its kind")
    func layoutGraphCarriesKind() throws {
        let graph = try #require(try Self.script(.modules, .svg).layoutGraph)
        for (name, kind) in Self.expected(.modules) {
            let node = try #require(graph.nodes.first { $0.label == name })
            #expect(node.stereotype == kind, "\(name)")
            #expect(node.module == nil, "\(name)")
        }
        #expect(graph.clusters.isEmpty)
    }

    // MARK: - The text formats, which already showed it

    @Test("the text formats show each node's module or target kind",
          arguments: [DiagramFormat.plantuml, .mermaid, .nomnoml], [DepsMode.types, .modules])
    func textFormatsShowModule(format: DiagramFormat, mode: DepsMode) throws {
        let text = try Self.script(mode, format).text
        let keyword = mode == .types ? "class" : "component"
        let nomnomlIds = format == .nomnoml ? try NomnomlGraph(parsing: text).nodes.map(\.id) : []
        for (name, label) in Self.expected(mode) {
            switch format {
            case .plantuml: #expect(text.contains("\(keyword) \"\(name)\" as \(name) <<\(label)>>"), "\(text)")
            case .mermaid: #expect(text.contains("\(name)[\"\(name)<br/>«\(label)»\"]"), "\(text)")
            default: #expect(nomnomlIds.contains("\(name) «\(label)»"), "\(nomnomlIds)")
            }
        }
    }

    /// The SVG puts a cycle node's `warning` in the stereotype slot, and Studio colours its
    /// header pink from it, so a module stereotype must not displace it. Its module goes in
    /// `module`, as every other node's does.
    @Test("a cycle node in a package keeps its warning in the layout graph, and its module")
    func cycleNodeKeepsWarning() throws {
        let model = DependencyGraphModel(edges: [
            DependencyEdge(from: "CA", to: "CB", kind: .conforms, fromModule: "Core", toModule: "Core"),
            DependencyEdge(from: "CB", to: "CA", kind: .inherits, fromModule: "Core", toModule: "Core")
        ])
        let graph = try #require(DepsScript(model: model, configuration: Configuration(format: .svg)).layoutGraph)
        #expect(graph.nodes.map(\.stereotype) == ["warning", "warning"])
        #expect(graph.nodes.map(\.module) == ["Core", "Core"])
        let text = DepsScript(model: model, configuration: Configuration(format: .plantuml)).text
        #expect(text.contains("class \"CA\" as CA <<Core>>") && text.contains("Cyclic nodes: CA, CB"), "\(text)")
    }
}
