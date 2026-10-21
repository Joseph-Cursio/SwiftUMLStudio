import Testing
@testable import SwiftUMLBridgeFramework

// Fixtures and readers shared by the class-diagram suites, each of which used to declare a
// private copy (#209).

/// One file of a fixture that spans several files: its name, which tells declarations apart as a
/// path on disk does, and its source.
typealias SourceFile = (name: String, source: String)

/// A class diagram of `source` in `format`. An option left at its default is the one a run with
/// no config file uses.
func classDiagram(
    _ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all,
    nestedTypes: Bool = true, access: [AccessLevel] = ElementOptions.defaultAccessLevels,
    exclude: [String]? = nil, relationships: RelationshipOptions = RelationshipOptions()
) -> DiagramScript {
    let elements = ElementOptions(
        havingAccessLevel: access, showNestedTypes: nestedTypes, showExtensions: extensions, exclude: exclude
    )
    let configuration = Configuration(elements: elements, relationships: relationships, format: format)
    return ClassDiagramGenerator().generateScript(for: source, with: configuration)
}

/// The declarations of `files`, each parsed apart and stamped as declared in its own file, as
/// they are read from disk.
func parsedFiles(_ files: [SourceFile]) throws -> [SyntaxStructure] {
    try files.flatMap { file in
        let items = try #require(SyntaxStructure.create(from: file.source)?.substructure)
        func stamp(_ item: SyntaxStructure) {
            item.sourceLocation = SourceLocation(filePath: file.name, line: 1, column: 1)
            item.substructure?.forEach(stamp)
        }
        items.forEach(stamp)
        return items
    }
}

/// A class diagram of `files`, read as `parsedFiles(_:)` reads them.
func classDiagram(
    _ files: [SourceFile], _ format: DiagramFormat, _ extensions: ExtensionVisualization = .all,
    access: [AccessLevel] = ElementOptions.defaultAccessLevels
) throws -> DiagramScript {
    let elements = ElementOptions(havingAccessLevel: access, showExtensions: extensions)
    let configuration = Configuration(elements: elements, format: format)
    return DiagramScript(items: try parsedFiles(files), configuration: configuration)
}

/// Each supertype edge drawn from `child` in a diagram of `files`, as `end arrow`: `P <|--`,
/// `P <|..`, or Nomnoml's `P -:>` and `P --:>`.
func supertypeEdges(
    from child: String, _ files: [SourceFile], _ format: DiagramFormat,
    _ extensions: ExtensionVisualization = .all, access: [AccessLevel] = ElementOptions.defaultAccessLevels
) throws -> [String] {
    let text = try classDiagram(files, format, extensions, access: access).text
    return text.split(separator: "\n").compactMap { line -> String? in
        if format == .nomnoml {
            // `[child] -:> label [parent]`
            let words = line.split(separator: " ")
            guard words.first == "[\(child)]", words.count >= 3, let last = words.last else { return nil }
            return "\(last.dropFirst().dropLast()) \(words[1])"
        }
        // `parent <|-- child : label`
        let words = line.split(separator: " ")
        guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
        return "\(words[0]) \(words[1])"
    }
}

/// The id each supertype edge from `child` ends on in a diagram of `source`, and in SVG the
/// members of that node, which tell the boxes apart.
func supertypeEdgeEnds(
    from child: String, _ source: String, _ format: DiagramFormat, _ extensions: ExtensionVisualization,
    nestedTypes: Bool = true
) -> [String] {
    let drawn = classDiagram(source, format, extensions, nestedTypes: nestedTypes)
    switch format {
    case .svg:
        let graph = drawn.layoutGraph
        return graph?.edges.filter { $0.sourceId == child && $0.style != .composition }.map { edge in
            (graph?.nodes.first { $0.id == edge.targetId }?.compartments.flatMap(\.items) ?? []).joined()
        } ?? []
    case .nomnoml:
        return drawn.text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("[\(child)] -"), let open = line.lastIndex(of: "[") else { return nil }
            return String(line[line.index(after: open)...].dropLast())
        }
    default:
        return drawn.text.split(separator: "\n").compactMap { line -> String? in
            let words = line.split(separator: " ")
            guard words.count >= 3, ["<|--", "<|.."].contains(words[1]), words[2] == child else { return nil }
            return String(words[0])
        }
    }
}

/// The edge lines of a PlantUML, Mermaid or Nomnoml script.
func edgeLines(_ script: String) -> [String] {
    let arrows = ["<|--", "<|..", "<..", "+--"]
    return script.split(separator: "\n").map(String.init).filter { line in
        arrows.contains { line.contains(" \($0) ") } || (line.hasPrefix("[") && !line.hasPrefix("[<"))
    }
}
