// MARK: - Activity Diagram Generator Protocol

/// Abstraction for activity (control-flow) diagram generation, enabling mock injection in tests.
public protocol ActivityDiagramGenerating: Sendable {
    /// Find all potential entry points (`Type.method`) in the given sources.
    func findEntryPoints(for paths: [String]) -> [String]

    /// Generate an activity diagram script for a specific entry function.
    func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        with configuration: Configuration
    ) -> ActivityScript
}
