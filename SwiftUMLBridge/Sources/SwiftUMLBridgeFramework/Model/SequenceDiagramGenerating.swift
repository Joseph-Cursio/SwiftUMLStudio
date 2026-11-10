// MARK: - Sequence Diagram Generator Protocol

/// Abstraction for sequence diagram generation, enabling mock injection in tests.
public protocol SequenceDiagramGenerating: Sendable {
    func findEntryPoints(for paths: [String]) -> [String]

    func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        depth: Int,
        with configuration: Configuration
    ) -> SequenceScript
}
