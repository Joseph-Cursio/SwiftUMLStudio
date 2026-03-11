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
            VStack(spacing: 0) {
                FileBrowserSidebar(viewModel: viewModel)
                Divider()
                HistorySidebar(viewModel: viewModel)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            sourceEditor
                .navigationSplitViewColumnWidth(min: 300, ideal: 400)
                .navigationTitle(viewModel.selectedFileURL?.lastPathComponent ?? "Source")
        } detail: {
            DiagramDetailView(viewModel: viewModel)
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
                    SequenceControlsView(viewModel: viewModel)
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
        .onChange(of: viewModel.selectedPaths) {
            viewModel.rebuildFileTree()
            viewModel.generate()
            if viewModel.diagramMode == .sequenceDiagram {
                viewModel.refreshEntryPoints()
            }
        }
        .onChange(of: viewModel.selectedFileURL) {
            viewModel.selectFile(viewModel.selectedFileURL)
        }
        .onChange(of: viewModel.diagramMode) {
            viewModel.generate()
            if viewModel.diagramMode == .sequenceDiagram && !viewModel.selectedPaths.isEmpty {
                viewModel.refreshEntryPoints()
            }
        }
        .onChange(of: viewModel.diagramFormat) { viewModel.generate() }
        .onChange(of: viewModel.entryPoint) { viewModel.generate() }
        .onChange(of: viewModel.sequenceDepth) { viewModel.generate() }
        .onChange(of: viewModel.depsMode) { viewModel.generate() }
    }

    // MARK: - Subviews

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

    private var sourceEditor: some View {
        Group {
            if viewModel.selectedFileURL != nil {
                TextEditor(text: .constant(viewModel.selectedFileContent))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background)
                    .disabled(true)
            } else {
                ContentUnavailableView(
                    "Select a file",
                    systemImage: "doc.text",
                    description: Text("Choose a Swift file from the browser to view its source.")
                )
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
        viewModel.selectedPaths = panel.urls.map { $0.path() }
        viewModel.generate()
    }
}

// MARK: - Sidebar Views

struct FileBrowserSidebar: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        List(selection: $viewModel.selectedFileURL) {
            Section("Files") {
                if viewModel.fileTree.isEmpty {
                    ContentUnavailableView("No files opened", systemImage: "doc")
                } else {
                    OutlineGroup(viewModel.fileTree, children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "swift")
                            .tag(node.url)
                    }
                }
            }
        }
        .accessibilityIdentifier("fileBrowser")
    }
}

struct HistorySidebar: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        List(selection: $viewModel.selectedHistoryItem) {
            Section("History") {
                if viewModel.history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock")
                } else {
                    ForEach(viewModel.history) { item in
                        ContentView.HistoryItemRow(item: item)
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
        .onChange(of: viewModel.selectedHistoryItem) {
            if let item = viewModel.selectedHistoryItem {
                viewModel.loadDiagram(item)
            }
        }
    }
}

// MARK: - Detail Pane

struct DiagramDetailView: View {
    let viewModel: DiagramViewModel
    @State private var selectedTab: DetailTab = .preview

    enum DetailTab: String, CaseIterable {
        case preview = "Preview"
        case markup = "Markup"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiagramPreviewView(viewModel: viewModel)
                .tabItem { Label("Preview", systemImage: "eye") }
                .tag(DetailTab.preview)

            MarkupView(viewModel: viewModel)
                .tabItem { Label("Markup", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DetailTab.markup)
        }
        .accessibilityIdentifier("detailTabs")
    }
}

struct DiagramPreviewView: View {
    let viewModel: DiagramViewModel

    var body: some View {
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
}

struct MarkupView: View {
    let viewModel: DiagramViewModel

    var body: some View {
        Group {
            if let script = viewModel.currentScript {
                TextEditor(text: .constant(script.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background)
                    .disabled(true)
            } else {
                ContentUnavailableView("No diagram generated", systemImage: "doc.text")
            }
        }
    }
}

struct SequenceControlsView: View {
    @Bindable var viewModel: DiagramViewModel

    var body: some View {
        HStack(spacing: 2) {
            TextField("Type.method", text: $viewModel.entryPoint)
                .frame(width: 140)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("entryPointField")

            Menu("Entry Points", systemImage: "chevron.down") {
                if viewModel.availableEntryPoints.isEmpty {
                    Text("No entry points found")
                } else {
                    ForEach(viewModel.availableEntryPoints, id: \.self) { entryPoint in
                        Button(entryPoint) {
                            viewModel.entryPoint = entryPoint
                        }
                    }
                }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .accessibilityIdentifier("entryPointMenu")
            .help("Select from discovered entry points")
        }

        Stepper(
            "Depth: \(viewModel.sequenceDepth)",
            value: $viewModel.sequenceDepth,
            in: 1...10
        )
        .frame(width: 120)
        .accessibilityIdentifier("depthStepper")
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
}

#Preview {
    ContentView()
}
