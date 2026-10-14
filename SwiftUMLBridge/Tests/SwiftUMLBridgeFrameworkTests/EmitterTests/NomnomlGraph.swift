import Foundation
import JavaScriptCore

/// What nomnoml builds from a diagram: the nodes and edges `nomnoml.parse` returns, read with the
/// copy Studio's preview draws with (`SwiftUMLStudio/Resources/nomnoml.js`, 1.7.0), so a test sees
/// the diagram as nomnoml does rather than as its text reads (#69).
///
/// nomnoml names a node by its `id=` attribute, or else by the first line of its title. It merges
/// nodes that share a name, keeping the one with the most compartments, and gives an edge end that
/// names no node a plain box of its own.
struct NomnomlGraph: Decodable {
    struct Node: Decodable, Equatable {
        let id: String
        let type: String
        /// The lines of each compartment, the title first.
        let compartments: [[String]]

        var title: String { compartments.first?.first ?? "" }
    }

    struct Edge: Decodable, Equatable {
        let start: String
        let type: String
        let end: String
        let startLabel: String
        let endLabel: String
    }

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    let nodes: [Node]
    let edges: [Edge]

    /// The repository's `SwiftUMLStudio/Resources`, five levels above this file.
    private static let resources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SwiftUMLStudio/Resources")

    private static let read = """
        (function (source) {
            const root = nomnoml.parse(source).root;
            return JSON.stringify({
                nodes: root.nodes.map(node => ({
                    id: node.id, type: node.type, compartments: node.parts.map(part => part.lines)
                })),
                edges: root.assocs.map(assoc => ({
                    start: assoc.start, type: assoc.type, end: assoc.end,
                    startLabel: assoc.startLabel.text, endLabel: assoc.endLabel.text
                }))
            });
        })
        """

    /// Parses `text` with the bundled nomnoml; throws the error that fails the whole diagram.
    init(parsing text: String) throws {
        guard let context = JSContext() else { throw ParseError(description: "no JavaScript context") }
        for script in ["graphre.js", "nomnoml.js"] {
            context.evaluateScript(try String(contentsOf: Self.resources.appending(path: script), encoding: .utf8))
        }
        let json = context.evaluateScript(Self.read)?.call(withArguments: [text])
        if let exception = context.exception {
            throw ParseError(description: exception.toString() ?? "nomnoml threw")
        }
        guard let json, json.isString, let data = json.toString()?.data(using: .utf8) else {
            throw ParseError(description: "nomnoml returned no graph")
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    func node(_ id: String) -> Node? {
        nodes.first { $0.id == id }
    }
}
