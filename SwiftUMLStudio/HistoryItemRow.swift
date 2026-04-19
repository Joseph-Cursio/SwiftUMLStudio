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
        let mode = item.mode ?? "Diagram"
        if mode == DiagramMode.dependencyGraph.rawValue, let detail = item.entryPoint {
            return "\(mode) (\(detail))"
        }
        return mode
    }
}
