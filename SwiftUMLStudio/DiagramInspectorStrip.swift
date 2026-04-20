import SwiftUI
import SwiftUMLBridgeFramework

struct DiagramInspectorStrip: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("Format", selection: $viewModel.diagramFormat) {
                Text("PlantUML").tag(DiagramFormat.plantuml)
                Text("Mermaid").tag(DiagramFormat.mermaid)
                Text("Nomnoml").tag(DiagramFormat.nomnoml)
                Text("SVG").tag(DiagramFormat.svg)
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .accessibilityIdentifier("formatPicker")

            Divider().frame(height: 20)

            modeSpecificControls

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var modeSpecificControls: some View {
        switch viewModel.diagramMode {
        case .sequenceDiagram:
            SequenceControlsView(viewModel: viewModel)
        case .activityDiagram:
            ActivityControlsView(viewModel: viewModel)
        case .dependencyGraph:
            depsPicker
        case .stateMachine:
            stateMachinePicker
        case .classDiagram:
            EmptyView()
        }
    }

    private var depsPicker: some View {
        Picker("Deps Mode", selection: $viewModel.depsMode) {
            ForEach(DepsMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .accessibilityIdentifier("depsModeControl")
    }

    private var stateMachinePicker: some View {
        Picker("State Machine", selection: $viewModel.stateIdentifier) {
            Text("—").tag("")
            ForEach(viewModel.availableStateMachines, id: \.identifier) { candidate in
                Label {
                    Text(candidate.identifier)
                } icon: {
                    Image(systemName: confidenceSymbol(candidate.confidence))
                        .foregroundStyle(confidenceColor(candidate.confidence))
                }
                .tag(candidate.identifier)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 260)
        .accessibilityIdentifier("stateMachinePicker")
    }

    private func confidenceSymbol(_ confidence: DetectionConfidence) -> String {
        switch confidence {
        case .high: return "circle.fill"
        case .medium: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.triangle.fill"
        }
    }

    private func confidenceColor(_ confidence: DetectionConfidence) -> SwiftUI.Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}
