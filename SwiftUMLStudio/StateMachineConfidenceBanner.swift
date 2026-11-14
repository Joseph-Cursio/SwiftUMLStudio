import SwiftUI
import SwiftUMLBridgeFramework

struct StateMachineConfidenceBanner: View {
    let model: StateMachineModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.subheadline.bold())
                ForEach(model.notes, id: \.self) { note in
                    Text("• \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(tint.opacity(0.3)), alignment: .bottom)
        .accessibilityIdentifier("stateMachineConfidenceBanner")
    }

    var symbol: String {
        model.confidence == .medium ? "info.circle.fill" : "exclamationmark.triangle.fill"
    }

    var tint: SwiftUI.Color {
        model.confidence == .medium ? .orange : .red
    }

    var headline: String {
        switch model.confidence {
        case .medium: return "Partially inferred state machine"
        case .low: return "Low-confidence state machine"
        case .high: return ""
        }
    }
}
