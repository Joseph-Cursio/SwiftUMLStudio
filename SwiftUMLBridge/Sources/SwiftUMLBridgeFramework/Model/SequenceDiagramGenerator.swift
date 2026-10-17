import Foundation

/// Generates sequence diagram scripts from Swift source files.
public struct SequenceDiagramGenerator: SequenceDiagramGenerating, Sendable {
    public init() {}

    /// Find all potential entry points (Type.method) in the given source files.
    ///
    /// - Parameter paths: Paths to Swift source files or directories.
    /// - Returns: A sorted list of "Type.method" strings found in the sources.
    public func findEntryPoints(for paths: [String]) -> [String] {
        CallGraphExtractor.entryPoints(for: paths)
    }

    /// Generate a `SequenceScript` from Swift files at the given paths.
    ///
    /// - Parameters:
    ///   - paths: Paths to Swift source files or directories.
    ///   - entryType: The type containing the entry-point method. A name in it may be written
    ///     with backticks: `` `Plain` `` is the listed `Plain`.
    ///   - entryMethod: The entry-point method name, read the same way.
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
        let sources = CallGraphExtractor.readSources(for: paths)
        var typeLocations: [String: SourceLocation] = [:]
        // Names and locations need no SourceKit pass. Parsed once, for both of their uses.
        let declarations = sources.flatMap {
            SyntaxStructure.declarations(in: $0.contents, file: $0.file)?.substructure ?? []
        }
        // A typealias is no participant's declaration (#125).
        for item in declarations where item.kind != .typealias {
            if let name = item.name, let location = item.sourceLocation, typeLocations[name] == nil {
                typeLocations[name] = location
            }
        }
        let aliases = TypeAliasResolver(items: declarations)
        let allEdges = sources.flatMap {
            CallGraphExtractor.extract(from: $0.contents, file: $0.file, aliases: aliases).edges
        }

        let listed = CallGraphExtractor.listedEntryPoint(type: entryType, method: entryMethod)
        // `--entry Alias.start` is the aliased type's `start`, as its extension is (#125).
        let entry = (type: aliases.resolve(listed.type, in: nil), method: listed.method)
        let callGraph = CallGraph(edges: allEdges)
        let traversed = callGraph.traverse(from: entry.type, entryMethod: entry.method, maxDepth: depth)
        return SequenceScript(
            traversedEdges: traversed,
            entryType: entry.type,
            entryMethod: entry.method,
            configuration: configuration,
            typeLocations: typeLocations
        )
    }
}
