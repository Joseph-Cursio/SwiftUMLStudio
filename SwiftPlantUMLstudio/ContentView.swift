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
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
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
        // Automatic generation triggers on any configuration change
        .onChange(of: viewModel.selectedPaths) { viewModel.generate() }
        .onChange(of: viewModel.diagramMode) { viewModel.generate() }
        .onChange(of: viewModel.diagramFormat) { viewModel.generate() }
        .onChange(of: viewModel.entryPoint) { viewModel.generate() }
        .onChange(of: viewModel.sequenceDepth) { viewModel.generate() }
        .onChange(of: viewModel.depsMode) { viewModel.generate() }
    }

    // MARK: - Subviews

    private var historySidebar: some View {
        @Bindable var viewModel = viewModel
        return List(selection: $viewModel.selectedHistoryItem) {
            Section("History") {
                if viewModel.history.isEmpty {
                    NoHistoryView()
                } else {
                    ForEach(viewModel.history) { item in
                        HistoryItemRow(item: item)
                            .tag(item)
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
        .onChange(of: viewModel.selectedHistoryItem) { _, newValue in
            if let item = newValue {
                viewModel.loadDiagram(item)
            }
        }
    }

    private struct NoHistoryView: View {
        var body: some View {
            Text("No history yet")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private struct HistoryItemRow: View {
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
                .font(.caption2)
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

    private var sourceEditor: some View {
        TextEditor(text: .constant(viewModel.currentScript?.text ?? ""))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
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
                Text("Enter an entry point (e.g. MyType.myMethod) to generate a diagram.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("entryPointPrompt")
            } else {
                Text("Select Swift source files or a folder to generate a diagram.")
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
        Button("Save", systemImage: "square.and.arrow.down") {
            viewModel.save()
        }
        .keyboardShortcut("s", modifiers: .command)
        .help("Save to history (⌘S)")
        .disabled(viewModel.currentScript == nil || viewModel.isGenerating)
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
        viewModel.generate()
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

#Preview {
    ContentView()
}
