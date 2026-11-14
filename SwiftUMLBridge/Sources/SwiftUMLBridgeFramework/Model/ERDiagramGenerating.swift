// MARK: - ER Diagram Generator Protocol

/// Abstraction for Entity-Relationship diagram generation, enabling mock
/// injection in tests. Unlike behavioral diagrams, an ER diagram covers the
/// whole project in one pass, so there is no entry-point selector.
public protocol ERDiagramGenerating: Sendable {
    /// Generate an ER diagram script for the persisted types in the given sources.
    func generateScript(
        for paths: [String],
        with configuration: Configuration
    ) -> ERScript
}
