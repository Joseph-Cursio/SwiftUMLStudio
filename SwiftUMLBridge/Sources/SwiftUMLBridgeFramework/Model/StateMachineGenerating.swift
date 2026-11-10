import Foundation

// MARK: - State Machine Generator Protocol

/// Abstraction for state machine diagram generation, enabling mock injection in tests.
public protocol StateMachineGenerating: Sendable {
    /// Find all candidate state machines (host type + enum type pairs) in the given sources.
    func findCandidates(for paths: [String]) -> [StateMachineModel]

    /// Generate a `StateScript` for a specific candidate identified by `"HostType.EnumType"`.
    func generateScript(
        for paths: [String],
        stateIdentifier: String,
        with configuration: Configuration
    ) -> StateScript
}
