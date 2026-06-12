import Foundation

/// Generates activity (control-flow) diagram scripts for a chosen entry function.
public struct ActivityDiagramGenerator: ActivityDiagramGenerating, @unchecked Sendable {
    public init() {}

    /// Find all potential entry points (`Type.method`) in the given source files.
    public func findEntryPoints(for paths: [String]) -> [String] {
        CallGraphExtractor.entryPoints(for: paths)
    }

    /// Generate an `ActivityScript` from Swift files at the given paths.
    ///
    /// Walks files in order; the first file that contains a matching entry point wins.
    /// Returns an empty script when no file contains the entry point.
    public func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        with configuration: Configuration = .default
    ) -> ActivityScript {
        let files = FileCollector().getFiles(for: paths)
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if let graph = ActivityFlowExtractor.extract(
                from: source, entryType: entryType, entryMethod: entryMethod
            ) {
                return ActivityScript(graph: graph, configuration: configuration)
            }
        }
        return ActivityScript(
            graph: ActivityGraph(entryType: entryType, entryMethod: entryMethod),
            configuration: configuration
        )
    }
}
