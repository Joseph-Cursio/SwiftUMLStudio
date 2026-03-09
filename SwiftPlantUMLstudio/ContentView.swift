//
//  ContentView.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/26/26.
//

import SwiftUI
import SwiftUMLBridgeFramework
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = DiagramViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            historySidebar
        } content: {
            sourceEditor
                .navigationSplitViewColumnWidth(min: 300, ideal: 400)
                .navigationTitle("Markup")
        } detail: {
            diagramPreview
                .navigationTitle("Preview")
        }
        // 1 400 px minimum ensures all toolbar items are visible without overflow.
        .frame(minWidth: 1400)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                openButton
                pathSummaryText
                modePicker(viewModel: $viewModel)
                formatPicker(viewModel: $viewModel)

                if viewModel.diagramMode == .sequenceDiagram {
                    sequenceControls(viewModel: $viewModel)
                }

                if viewModel.diagramMode == .dependencyGraph {
                    dependencyControls(viewModel: $viewModel)
                }

                generateButton
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            openPanel()
        }
        .task {
            viewModel.loadHistory()
        }
    }

    // MARK: - Subviews

    private var historySidebar: some View {
        List {
            Section("History") {
                if viewModel.history.isEmpty {
                    Text("No history yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(viewModel.history) { item in
                        VStack(alignment: .leading) {
                            Text(item.mode ?? "Diagram")
                                .font(.headline)
                            if let timestamp = item.timestamp {
                                Text(timestamp, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.loadDiagram(item)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                viewModel.deleteHistoryItem(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("SwiftUML Studio")
    }

    private var sourceEditor: some View {
        TextEditor(text: .constant(viewModel.currentScript?.text ?? ""))
            .font(.system(.body, design: .monospaced))
            .disabled(true)
    }

    private var diagramPreview: some View {
        Group {
            if viewModel.isGenerating {
                ProgressView("Generating…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.currentScript != nil {
                DiagramWebView(script: viewModel.currentScript)
            } else if viewModel.diagramMode == .sequenceDiagram && viewModel.entryPoint.isEmpty {
                Text("Enter an entry point (e.g. MyType.myMethod), then click Generate.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("entryPointPrompt")
            } else {
                Text("Select Swift source files or a folder, then click Generate.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fileSelectionPrompt")
            }
        }
    }

    // MARK: - Toolbar Items

    private var openButton: some View {
        Button("Open…", systemImage: "folder") {
            openPanel()
        }
        .help("Open Swift files or directories (⌘O)")
    }

    private var pathSummaryText: some View {
        Text(viewModel.pathSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300, alignment: .leading)
    }

    private func modePicker(viewModel: Bindable<DiagramViewModel>) -> some View {
        Picker("Mode", selection: viewModel.diagramMode) {
            ForEach(DiagramMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 360)
        .accessibilityIdentifier("modePicker")
    }

    private func formatPicker(viewModel: Bindable<DiagramViewModel>) -> some View {
        Picker("Format", selection: viewModel.diagramFormat) {
            Text("PlantUML").tag(DiagramFormat.plantuml)
            Text("Mermaid").tag(DiagramFormat.mermaid)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
    }

    @ViewBuilder
    private func sequenceControls(viewModel: Bindable<DiagramViewModel>) -> some View {
        TextField("Type.method", text: viewModel.entryPoint)
            .frame(width: 160)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("entryPointField")

        Stepper(
            "Depth: \(viewModel.sequenceDepth.wrappedValue)",
            value: viewModel.sequenceDepth,
            in: 1...10
        )
        .frame(width: 120)
        .accessibilityIdentifier("depthStepper")
    }

    private func dependencyControls(viewModel: Bindable<DiagramViewModel>) -> some View {
        Picker("Deps Mode", selection: viewModel.depsMode) {
            ForEach(DepsMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .accessibilityIdentifier("depsModeControl")
    }

    private var generateButton: some View {
        Button("Generate", systemImage: "play.fill") {
            viewModel.generate()
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Generate diagram (⌘R)")
        .disabled(viewModel.selectedPaths.isEmpty || viewModel.isGenerating)
    }

    // MARK: - Logic

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.swiftSource]
        panel.canSelectHiddenExtension = true

        guard panel.runModal() == .OK else { return }
        viewModel.selectedPaths = panel.urls.map(\.path)
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

#Preview {
    ContentView()
}
