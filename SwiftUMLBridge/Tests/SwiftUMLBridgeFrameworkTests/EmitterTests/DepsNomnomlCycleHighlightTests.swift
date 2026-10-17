import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("A Nomnoml dependency graph draws its cycle's own boxes with the warning style")
struct DepsNomnomlCycleHighlightTests {

    /// One target, `Geometry`, whose `Shape` and `Drawable` form a cycle; `Circle` is not on it.
    private static let source = """
        class Shape: Drawable {}
        protocol Drawable: Shape {}
        final class Circle: Shape {}
        """

    private func nomnomlText(packageMode: Bool) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nomnoml-cycle-\(UUID().uuidString)", isDirectory: true)
        let targetDir = root.appendingPathComponent("Sources/Geometry", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.source.write(
            to: targetDir.appendingPathComponent("Shape.swift"), atomically: true, encoding: .utf8)

        var config = Configuration.default
        config.format = .nomnoml
        guard packageMode else {
            return DependencyGraphGenerator()
                .generateScript(for: [targetDir.path], mode: .types, with: config).text
        }
        let description = SPMPackageDescription(name: "Shapes", targets: [
            SPMTargetDescription(name: "Geometry", kind: .library, path: "Sources/Geometry",
                                 sources: ["Shape.swift"], dependencies: [])
        ])
        return DependencyGraphGenerator().generateScript(
            forPackage: description, packageRoot: root, mode: .types, with: config
        ).text
    }

    @Test("every box has an edge, and the cycle's boxes are the warning ones", arguments: [false, true])
    func cycleBoxesAreWarning(packageMode: Bool) throws {
        let text = try nomnomlText(packageMode: packageMode)
        let graph = try NomnomlGraph(parsing: text)
        let edgeEnds = Set(graph.edges.flatMap { [$0.start, $0.end] })

        #expect(graph.nodes.allSatisfy { edgeEnds.contains($0.id) }, "\(graph.nodes)\n\(text)")
        let warned = graph.nodes
            .filter { $0.type == "warning" && edgeEnds.contains($0.id) }
            .map(\.title)
            .sorted()
        let expected = packageMode ? ["Drawable «Geometry»", "Shape «Geometry»"] : ["Drawable", "Shape"]
        #expect(warned == expected, "\(graph.nodes)")
    }

    // MARK: - From a model

    private func graph(
        _ edges: [DependencyEdge], targetKinds: [String: SPMTargetDescription.Kind] = [:]
    ) throws -> (graph: NomnomlGraph, text: String) {
        var config = Configuration.default
        config.format = .nomnoml
        let model = DependencyGraphModel(edges: edges, targetKinds: targetKinds)
        let text = DepsScript(model: model, configuration: config).text
        return (try NomnomlGraph(parsing: text), text)
    }

    @Test("a modules cycle's boxes are the warning ones, and a box off the cycle is not")
    func modulesCycle() throws {
        let (graph, text) = try graph([
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Alpha", kind: .imports),
            DependencyEdge(from: "App", to: "Alpha", kind: .imports)
        ])
        let types = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.type) })
        #expect(types == ["Alpha": "warning", "Beta": "warning", "App": "class"], "\(text)")
    }

    @Test("a cycle between stereotyped targets colours the targets' own boxes")
    func stereotypedModulesCycle() throws {
        let (graph, text) = try graph([
            DependencyEdge(from: "Core", to: "UI", kind: .imports),
            DependencyEdge(from: "UI", to: "Core", kind: .imports)
        ], targetKinds: ["Core": .library, "UI": .executable])
        let types = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.type) })
        #expect(types == ["Core «library»": "warning", "UI «executable»": "warning"], "\(text)")
    }

    @Test("a node with an edge to itself is a warning box")
    func selfLoop() throws {
        let (graph, text) = try graph([
            DependencyEdge(from: "Node", to: "Node", kind: .inherits),
            DependencyEdge(from: "Leaf", to: "Node", kind: .inherits)
        ])
        let types = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.type) })
        #expect(types == ["Node": "warning", "Leaf": "class"], "\(text)")
    }

    @Test("a cycle node whose name nomnoml escapes keeps one box")
    func escapedName() throws {
        let (graph, text) = try graph([
            DependencyEdge(from: "Box<T>", to: "Wrap|Of", kind: .inherits),
            DependencyEdge(from: "Wrap|Of", to: "Box<T>", kind: .conforms)
        ])
        #expect(graph.nodes.count == 2, "\(graph.nodes)\n\(text)")
        #expect(graph.nodes.allSatisfy { $0.type == "warning" }, "\(graph.nodes)\n\(text)")
    }

    @Test("the warning style is declared once, however many nodes are on a cycle")
    func styleDeclaredOnce() throws {
        let (_, text) = try graph([
            DependencyEdge(from: "Alpha", to: "Beta", kind: .imports),
            DependencyEdge(from: "Beta", to: "Gamma", kind: .imports),
            DependencyEdge(from: "Gamma", to: "Alpha", kind: .imports)
        ])
        let directives = text.components(separatedBy: "\n")
            .filter { $0 == "#.warning: fill=#ffcccc stroke=#cc0000" }
        #expect(directives.count == 1, "\(text)")
    }
}
