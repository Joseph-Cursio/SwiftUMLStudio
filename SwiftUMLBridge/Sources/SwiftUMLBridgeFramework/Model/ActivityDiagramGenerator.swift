import Foundation

/// Generates activity (control-flow) diagram scripts for a chosen entry function.
public struct ActivityDiagramGenerator: ActivityDiagramGenerating, Sendable {
    public init() {}

    /// Find all potential entry points (`Type.method`) in the given source files.
    public func findEntryPoints(for paths: [String]) -> [String] {
        CallGraphExtractor.entryPoints(for: paths)
    }

    /// Generate an `ActivityScript` from Swift files at the given paths.
    ///
    /// Walks files in order; the first file that contains a matching entry point wins.
    /// Returns an empty script when no file contains the entry point. A name in `entryType` or
    /// `entryMethod` may be written with backticks: `` `Plain` `` is the listed `Plain`.
    public func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        with configuration: Configuration = .default
    ) -> ActivityScript {
        let listed = CallGraphExtractor.listedEntryPoint(type: entryType, method: entryMethod)
        let sources = CallGraphExtractor.readSources(for: paths)
        let aliases = TypeAliasResolver(sources: sources)
        // `--entry Alias.helper` is the aliased type's `helper`, as its extension is (#125).
        let entry = (type: aliases.resolve(listed.type, in: nil), method: listed.method)
        for source in sources {
            if let graph = ActivityFlowExtractor.extract(
                from: source.contents, entryType: entry.type, entryMethod: entry.method,
                file: source.file, aliases: aliases
            ) {
                return ActivityScript(graph: graph, configuration: configuration)
            }
        }
        return ActivityScript(
            graph: ActivityGraph(entryType: entry.type, entryMethod: entry.method),
            configuration: configuration
        )
    }
}
