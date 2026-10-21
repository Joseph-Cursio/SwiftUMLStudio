import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// The parser splits a composition `P & Q` into its parts on the syntax tree (#160), so an `&`
/// left in a supertype's name belongs to that one type: a generic argument, as in
/// `Base<any P & Q>`, or a raw identifier, as in `` `Read & Write` ``. No later reader splits it
/// again.
@Suite("An & inside one supertype's name is part of that name")
struct AmpersandInSupertypeNameTests {

    static let source = """
        protocol P {}
        protocol Q {}
        class Base<T> {}
        final class Sub: Base<any P & Q> {}
        protocol `Read & Write` {}
        struct File: `Read & Write` {}
        """

    @Test("PlantUML and Mermaid draw one edge to each supertype", arguments: [DiagramFormat.plantuml, .mermaid])
    func textEdges(format: DiagramFormat) {
        #expect(edgeLines(classDiagram(Self.source, format).text) == [
            "Base <|-- Sub : inherits",
            "`Read & Write` <|.. File : conforms to"
        ])
    }

    /// Nomnoml writes a space inside a name as a no-break space.
    @Test("Nomnoml draws one edge to each supertype")
    func nomnomlEdges() {
        #expect(edgeLines(classDiagram(Self.source, .nomnoml).text) == [
            "[Sub] -:> inherits [Base]",
            "[File] --:> conforms to [`Read\u{00A0}&\u{00A0}Write`]"
        ])
    }

    @Test("SVG draws one edge to each supertype")
    func svgEdges() throws {
        let graph = try #require(classDiagram(Self.source, .svg).layoutGraph)
        let labels = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.label) })
        #expect(graph.edges.map { "\(labels[$0.sourceId] ?? "?") -> \(labels[$0.targetId] ?? "?")" } == [
            "Sub -> Base", "File -> `Read & Write`"
        ])
    }

    @Test("deps --types draws one edge to each supertype")
    func depsEdges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AmpersandInSupertypeNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Source.swift")
        try Self.source.write(to: url, atomically: true, encoding: .utf8)
        let edges = DependencyGraphGenerator().extractEdges(for: [url.path], mode: .types)
        #expect(edges.map { "\($0.from) -> \($0.to)" } == ["Sub -> Base<any P & Q>", "File -> `Read & Write`"])
    }
}
