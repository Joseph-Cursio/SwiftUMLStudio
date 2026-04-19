import Foundation

/// Generates state machine diagram scripts from Swift source files.
public struct StateMachineGenerator: StateMachineGenerating, @unchecked Sendable {
    public init() {}

    /// Find all candidate state machines across the given source files.
    ///
    /// - Parameter paths: Paths to Swift source files or directories.
    /// - Returns: Sorted list of candidate `StateMachineModel`s, identified by `"HostType.EnumType"`.
    public func findCandidates(for paths: [String]) -> [StateMachineModel] {
        let files = FileCollector().getFiles(for: paths)
        var all: [StateMachineModel] = []

        for file in files {
            if let source = try? String(contentsOf: file, encoding: .utf8) {
                all.append(contentsOf: StateMachineExtractor.extract(from: source))
            }
        }

        // Merge candidates with the same (hostType, enumType) across files: union transitions.
        let bucketed = Dictionary(grouping: all) { $0.identifier }
        var merged: [StateMachineModel] = []
        for (_, group) in bucketed {
            guard let first = group.first else { continue }
            if group.count == 1 {
                merged.append(first)
                continue
            }
            var seen: Set<StateTransition> = []
            var transitions: [StateTransition] = []
            for model in group {
                for transition in model.transitions where !seen.contains(transition) {
                    seen.insert(transition)
                    transitions.append(transition)
                }
            }
            merged.append(StateMachineModel(
                hostType: first.hostType,
                enumType: first.enumType,
                states: first.states,
                transitions: transitions
            ))
        }

        return merged.sorted { $0.identifier < $1.identifier }
    }

    /// Generate a `StateScript` for a specific candidate.
    ///
    /// - Parameters:
    ///   - paths: Source paths to scan.
    ///   - stateIdentifier: `"HostType.EnumType"` identifier (see `StateMachineModel.identifier`).
    ///   - configuration: Diagram configuration (format, etc.).
    /// - Returns: A rendered `StateScript`, or `StateScript.empty` when no match.
    public func generateScript(
        for paths: [String],
        stateIdentifier: String,
        with configuration: Configuration = .default
    ) -> StateScript {
        let candidates = findCandidates(for: paths)
        guard let model = candidates.first(where: { $0.identifier == stateIdentifier }) else {
            return .empty
        }
        return StateScript(model: model, configuration: configuration)
    }
}
