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
    /// Draws the body the sequence diagram of the same entry starts from
    /// (`CallGraphExtractor.entryBody`), so the two draw the same code (#235). Returns an empty
    /// script when no file has one. A name in `entryType` or `entryMethod` may be written with
    /// backticks: `` `Plain` `` is the listed `Plain`.
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
        // the name can come to with a body for it. Every file is read for it, as a type of that
        // name read later can still be the one meant.
        let types = aliases.entryTypes(of: listed.type)
        let bodies = sources.flatMap {
            CallGraphExtractor.extract(from: $0.contents, file: $0.file, aliases: aliases).bodies
        }
        let chosen = CallGraphExtractor.entryBody(
            named: listed.type, among: types, method: listed.method, in: bodies
        )
        if let chosen, let source = sources.first(where: { $0.file == chosen.file }),
           let graph = ActivityFlowExtractor.extract(
               from: source.contents, entryType: chosen.type, entryMethod: listed.method,
               at: chosen.offset, file: source.file
           ) {
            return ActivityScript(graph: graph, configuration: configuration)
        }
        return ActivityScript(
            graph: ActivityGraph(entryType: types[0], entryMethod: listed.method),
            configuration: configuration
        )
    }
}
