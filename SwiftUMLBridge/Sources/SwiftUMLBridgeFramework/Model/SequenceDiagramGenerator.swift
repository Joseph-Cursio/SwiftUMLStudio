import Foundation

/// Generates sequence diagram scripts from Swift source files.
public struct SequenceDiagramGenerator {
    public init() {}

    /// Find all potential entry points (Type.method) in the given source files.
    ///
    /// - Parameter paths: Paths to Swift source files or directories.
    /// - Returns: A sorted list of "Type.method" strings found in the sources.
    public func findEntryPoints(for paths: [String]) -> [String] {
        let files = FileCollector().getFiles(for: paths)
        var allMethods = Set<String>()

        for file in files {
            if let source = try? String(contentsOf: file, encoding: .utf8) {
                let result = CallGraphExtractor.extract(from: source)
                allMethods.formUnion(result.methods)
            }
        }

        return allMethods.sorted()
    }

    /// Generate a `SequenceScript` from Swift files at the given paths.
    ///
    /// - Parameters:
    ///   - paths: Paths to Swift source files or directories.
    ///   - entryType: The type containing the entry-point method.
    ///   - entryMethod: The entry-point method name.
    ///   - depth: Maximum call depth to traverse (default: 3).
    ///   - configuration: Diagram configuration (format, etc.)
    /// - Returns: A rendered `SequenceScript`, or `SequenceScript.empty` when nothing is found.
    public func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        depth: Int = 3,
        with configuration: Configuration = .default
    ) -> SequenceScript {
        let files = FileCollector().getFiles(for: paths)
        var allEdges: [CallEdge] = []

        for file in files {
            if let source = try? String(contentsOf: file, encoding: .utf8) {
                let result = CallGraphExtractor.extract(from: source)
                allEdges.append(contentsOf: result.edges)
            }
        }

        let callGraph = CallGraph(edges: allEdges)
        let traversed = callGraph.traverse(from: entryType, entryMethod: entryMethod, maxDepth: depth)
        return SequenceScript(
            traversedEdges: traversed,
            entryType: entryType,
            entryMethod: entryMethod,
            configuration: configuration
        )
    }
}
