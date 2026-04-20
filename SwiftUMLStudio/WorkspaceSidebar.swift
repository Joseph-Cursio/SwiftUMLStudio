import SwiftUI

struct WorkspaceSidebar: View {
    @Bindable var viewModel: DiagramViewModel
    @State private var selectedTab: Tab = .files

    enum Tab: String, CaseIterable, Identifiable {
        case files = "Files"
        case history = "History"
        var id: String { rawValue }
    }

    var body: some View {
        VSplitView {
            DiagramPickerSection(viewModel: viewModel)
                .frame(minHeight: 120, idealHeight: 260)

            VStack(spacing: 0) {
                Picker("Sidebar", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityIdentifier("sidebarTabPicker")

                Divider()

                switch selectedTab {
                case .files:
                    FileBrowserSidebar(viewModel: viewModel)
                case .history:
                    HistorySidebar(viewModel: viewModel)
                }
            }
            .frame(minHeight: 120)
        }
        .navigationTitle("SwiftUML Studio")
    }
}

private struct DiagramPickerSection: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diagrams")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            List(selection: $viewModel.diagramMode) {
                Section("Structural") {
                    ForEach(structuralModes) { mode in
                        row(for: mode)
                    }
                }
                Section("Behavioral") {
                    ForEach(behavioralModes) { mode in
                        row(for: mode)
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("modePicker")
        }
    }

    private func row(for mode: DiagramMode) -> some View {
        Label(mode.rawValue, systemImage: symbol(for: mode))
            .tag(mode)
            .accessibilityIdentifier("modeRow.\(mode.rawValue)")
    }

    private var structuralModes: [DiagramMode] {
        [.classDiagram, .dependencyGraph]
    }

    private var behavioralModes: [DiagramMode] {
        [.sequenceDiagram, .activityDiagram, .stateMachine]
    }

    private func symbol(for mode: DiagramMode) -> String {
        switch mode {
        case .classDiagram: return "square.stack.3d.up"
        case .dependencyGraph: return "point.3.connected.trianglepath.dotted"
        case .sequenceDiagram: return "arrow.triangle.branch"
        case .activityDiagram: return "flowchart"
        case .stateMachine: return "circle.hexagonpath"
        }
    }
}
