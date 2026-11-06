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
        // `--entry Alias.helper` is the aliased type's `helper`, as its extension is (#125): the first
        // the name can come to with a body for it. Chosen before any graph is built, so a name that
        // is a typealias costs one more pass over the files, not one per declaration.
        let types = aliases.entryTypes(of: listed.type)
        let chosen = CallGraphExtractor.entryType(
            named: listed.type, among: types, method: listed.method,
            in: sources.map { CallGraphExtractor.extract(from: $0.contents, file: $0.file, aliases: aliases) }
        )
        if let chosen {
            for source in sources {
                if let graph = ActivityFlowExtractor.extract(
                    from: source.contents, entryType: chosen, entryMethod: listed.method,
                    file: source.file, aliases: aliases
                ) {
                    return ActivityScript(graph: graph, configuration: configuration)
                }
            }
        }
        return ActivityScript(
            graph: ActivityGraph(entryType: types[0], entryMethod: listed.method),
            configuration: configuration
        )
    }
}
