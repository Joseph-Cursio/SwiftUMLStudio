import SwiftUI

struct HistoryItemRow: View {
    let item: DiagramEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name ?? "Untitled Diagram")
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(displayMode)
                Text("•")
                if let timestamp = item.timestamp {
                    Text(timestamp, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var displayMode: String {
        Self.displayMode(mode: item.mode, entryPoint: item.entryPoint)
    }

    /// Pure formatter for the history-row mode label.
    /// - Parameters:
    ///   - mode: Raw `DiagramMode` value stored on the entity; `nil` falls back to `"Diagram"`.
    ///   - entryPoint: Entity's entry-point payload (sequence entry, deps mode, or state identifier).
    static func displayMode(mode: String?, entryPoint: String?) -> String {
        let mode = mode ?? "Diagram"
        // Dependency graph detail is always present when set.
        if mode == DiagramMode.dependencyGraph.rawValue, let detail = entryPoint {
            return "\(mode) (\(detail))"
        }
        // Sequence + state machine details are only shown when non-empty.
        let entryBearingModes: [String] = [
            DiagramMode.stateMachine.rawValue, DiagramMode.sequenceDiagram.rawValue
        ]
        if entryBearingModes.contains(mode), let detail = entryPoint, !detail.isEmpty {
            return "\(mode) (\(detail))"
        }
        return mode
    }
}
