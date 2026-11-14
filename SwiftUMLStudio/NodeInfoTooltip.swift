import SwiftUI
import SwiftUMLBridgeFramework

/// Compact floating panel summarising the currently-hovered diagram node.
/// Shown by `DiagramPreviewView` in the top-leading corner whenever
/// `DiagramViewport.hoveredNodeId` resolves to a node in the active graph.
struct NodeInfoTooltip: View {
    let label: String
    let stereotype: String?
    let sourceLocation: SourceLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let stereotype, !stereotype.isEmpty {
                    Text("«\(stereotype)»")
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                }
                Text(label).font(.callout.bold())
            }
            if let location = sourceLocation, !location.filePath.isEmpty {
                Text(Self.shortPath(for: location))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nodeInfoTooltip")
    }

    /// Returns "filename.swift:line", suitable for a compact tooltip.
    /// Exposed for testing.
    static func shortPath(for location: SourceLocation) -> String {
        let filename = location.filePath.split(separator: "/").last.map(String.init) ?? location.filePath
        return "\(filename):\(location.line)"
    }
}
