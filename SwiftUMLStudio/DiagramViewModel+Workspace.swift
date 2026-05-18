import Foundation
import SwiftData
import SwiftUMLBridgeFramework

/// Workspace-side `DiagramViewModel` behavior: history, snapshots, the file
/// tree, SPM package loading, and project analysis. Split out of
/// `DiagramViewModel.swift` so the core observable type stays focused on
/// diagram state and generation dispatch.
extension DiagramViewModel {

    // MARK: - History

    func loadHistory() {
        let descriptor = FetchDescriptor<DiagramEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        history = (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadDiagram(_ entity: DiagramEntity) {
        let modeString = entity.mode ?? ""
        let formatString = entity.format ?? ""

        diagramMode = DiagramMode(rawValue: modeString) ?? .classDiagram
        diagramFormat = DiagramFormat(rawValue: formatString) ?? .plantuml

        if diagramMode == .sequenceDiagram {
            entryPoint = entity.entryPoint ?? ""
            refreshEntryPoints()
        } else if diagramMode == .dependencyGraph {
            depsMode = DepsMode(rawValue: entity.entryPoint ?? "") ?? .types
        } else if diagramMode == .stateMachine {
            stateIdentifier = entity.entryPoint ?? ""
            refreshStateMachines()
        } else if diagramMode == .activityDiagram {
            entryPoint = entity.entryPoint ?? ""
            refreshEntryPoints()
        }

        sequenceDepth = entity.sequenceDepth

        restoreSelection(from: entity)

        if let text = entity.scriptText {
            restoredScript = SimpleDiagramScript(text: text, format: diagramFormat)
        } else {
            restoredScript = nil
        }
    }

    /// Restore `selectedPaths` from a persisted entity, preferring stored
    /// security-scoped bookmarks (which carry sandbox read access across
    /// launches) and falling back to the raw path strings for legacy entities
    /// saved before bookmark capture was wired up.
    private func restoreSelection(from entity: DiagramEntity) {
        let storedBookmarks = entity.decodedPathBookmarks
        let storedPaths: [String]
        if let pathsData = entity.paths,
           let decoded = try? JSONDecoder().decode([String].self, from: pathsData) {
            storedPaths = decoded
        } else {
            storedPaths = []
        }

        guard !storedBookmarks.isEmpty else {
            #if APP_STORE_BUILD
            // Legacy entity (pre-bookmark) under sandbox: the saved raw paths
            // carry no sandbox access right, so restoring them would silently
            // produce empty diagrams. Drop the selection and notify.
            applySelection(paths: [], bookmarks: [], urls: [])
            if !storedPaths.isEmpty {
                setRestoreWarning(droppedCount: storedPaths.count)
            }
            #else
            applySelection(paths: storedPaths, bookmarks: [], urls: [])
            #endif
            return
        }

        var resolvedPaths: [String] = []
        var resolvedBookmarks: [Data?] = []
        var resolvedURLs: [URL] = []
        #if APP_STORE_BUILD
        var droppedFallbackCount = 0
        #endif
        for (idx, bookmark) in storedBookmarks.enumerated() {
            if let bookmark, let result = SecurityScopedURL.resolveURL(from: bookmark) {
                resolvedURLs.append(result.url)
                resolvedPaths.append(result.url.path())
                // Stale bookmarks regenerate via `bookmarkToPersist`. Storing
                // `nil` would silently strip sandbox access on the next launch
                // (path-only fallback isn't readable under sandbox).
                resolvedBookmarks.append(SecurityScopedURL.bookmarkToPersist(
                    original: bookmark,
                    resolvedURL: result.url,
                    isStale: result.isStale
                ))
                continue
            }
            guard idx < storedPaths.count else { continue }
            #if APP_STORE_BUILD
            // Sandbox can't read a raw path without an accompanying bookmark —
            // keeping the entry would silently produce empty diagrams. Drop
            // and notify; the user can re-pick via the file picker.
            droppedFallbackCount += 1
            #else
            resolvedPaths.append(storedPaths[idx])
            resolvedBookmarks.append(nil)
            #endif
        }
        applySelection(paths: resolvedPaths, bookmarks: resolvedBookmarks, urls: resolvedURLs)
        #if APP_STORE_BUILD
        if droppedFallbackCount > 0 {
            setRestoreWarning(droppedCount: droppedFallbackCount)
        }
        #endif
    }

    #if APP_STORE_BUILD
    /// Surface a user-facing warning when restoring a snapshot dropped one or
    /// more paths the sandboxed app can't read. Routed through `errorMessage`
    /// so the eventual UI surface picks it up alongside generation errors.
    private func setRestoreWarning(droppedCount: Int) {
        let suffix = droppedCount == 1 ? "file" : "files"
        errorMessage = "\(droppedCount) saved \(suffix) couldn't be restored "
            + "(moved, deleted, or never re-granted access). Re-open via the "
            + "file picker to include them again."
    }
    #endif

    func deleteHistoryItem(_ entity: DiagramEntity) {
        if selectedHistoryItem == entity {
            selectedHistoryItem = nil
            restoredScript = nil
        }
        modelContext.delete(entity)
        try? modelContext.save()
        loadHistory()
    }

    // MARK: - File Tree

    func rebuildFileTree() {
        fileTree = FileNode.buildTree(from: selectedPaths)
        if let url = selectedFileURL {
            let allURLs = FileNode.allLeafURLs(from: fileTree)
            if !allURLs.contains(url) {
                selectedFileURL = nil
                selectedFileContent = ""
            }
        }
        if selectedFileURL == nil {
            if let firstURL = FileNode.allLeafURLs(from: fileTree).first {
                selectFile(firstURL)
            }
        }
    }

    func selectFile(_ url: URL?) {
        selectedFileURL = url
        highlightedSourceLine = nil
        guard let url else {
            selectedFileContent = ""
            return
        }
        selectedFileContent = (try? String(contentsOf: url, encoding: .utf8))
            ?? "// Could not read file"
    }

    /// Open the file containing the given declaration in `SourceEditorView`
    /// and request that its line be highlighted. Used by Phase 4's
    /// "Reveal in Source" diagram navigation.
    func revealSource(at location: SourceLocation) {
        guard !location.filePath.isEmpty else { return }
        let url = URL(fileURLWithPath: location.filePath)
        selectFile(url)
        highlightedSourceLine = location.line
    }

    // MARK: - Snapshots

    func loadSnapshots() {
        snapshots = SnapshotManager.fetchSnapshots(modelContext: modelContext)
    }

    func saveSnapshot(isProUnlocked: Bool) {
        guard isProUnlocked, let summary = projectSummary else { return }
        SnapshotManager.saveSnapshot(
            from: summary,
            paths: selectedPaths,
            bookmarks: selectedPathBookmarks,
            modelContext: modelContext
        )
        loadSnapshots()
        updateArchitectureDiff()
        ReviewReminderManager.rescheduleIfEnabled()
    }

    func deleteSnapshot(_ snapshot: ProjectSnapshot) {
        SnapshotManager.deleteSnapshot(snapshot, modelContext: modelContext)
        loadSnapshots()
        updateArchitectureDiff()
    }

    func updateArchitectureDiff() {
        guard let summary = projectSummary, !selectedPaths.isEmpty else {
            architectureDiff = nil
            return
        }
        if let previous = SnapshotManager.latestSnapshot(
            for: selectedPaths, modelContext: modelContext
        ) {
            architectureDiff = SnapshotManager.computeDiff(current: summary, previous: previous)
        } else {
            architectureDiff = nil
        }
    }

    // MARK: - Project Analysis

    func analyzeProject(isProUnlocked: Bool = true) {
        guard !selectedPaths.isEmpty else {
            projectSummary = nil
            insights = []
            suggestions = []
            return
        }
        let paths = selectedPaths
        let proUnlocked = isProUnlocked
        let description = packageDescription
        let root = packageRoot
        Task {
            let (summary, newInsights, newSuggestions) = await Task.detached(
                priority: .userInitiated
            ) {
                let result: ProjectSummary
                if let description, let root {
                    result = ProjectAnalyzer.analyze(package: description, packageRoot: root)
                } else {
                    result = ProjectAnalyzer.analyze(paths: paths)
                }
                let insights = InsightEngine.generate(from: result)
                let suggestions = SuggestionEngine.generate(
                    from: result, isProUnlocked: proUnlocked
                )
                return (result, insights, suggestions)
            }.value
            projectSummary = summary
            insights = newInsights
            suggestions = newSuggestions
            updateArchitectureDiff()
        }
    }

    // MARK: - SPM Package

    /// Load an SPM package from disk and switch class-diagram generation into
    /// module-aware mode. The package root is the directory containing
    /// `Package.swift`. Runs `swift package describe --type json` off the main
    /// actor since the underlying Process call blocks.
    func loadPackage(at packageRoot: URL) async {
        packageLoadError = nil
        #if APP_STORE_BUILD
        // SPMPackageReader.describe shells out to `swift package describe`,
        // which the macOS App Sandbox blocks. Surface a clear error instead
        // of attempting (and trapping) the Process() call.
        packageLoadError = "Opening a Swift Package isn't supported in the "
            + "App Store build of SwiftUMLStudio. Use the direct-download "
            + "version for SPM support."
        return
        #else
        let result = await Task.detached(priority: .userInitiated) {
            try? SPMPackageReader.describe(at: packageRoot)
        }.value
        guard let description = result else {
            packageLoadError = "Failed to read SPM package at \(packageRoot.lastPathComponent). "
                + "Make sure `swift package describe` succeeds in this directory."
            return
        }
        self.packageRoot = packageRoot
        self.packageDescription = description
        // Replace whatever loose-files selection was active with the package's
        // own source paths so other generators (sequence, deps) keep working.
        let sourcePaths = description.sourceFileToModuleMap(packageRoot: packageRoot).keys.sorted()
        self.selectedPaths = sourcePaths
        #endif
    }

    /// Clear the loaded package so generation falls back to loose files.
    func unloadPackage() {
        packageRoot = nil
        packageDescription = nil
        packageLoadError = nil
    }

    // MARK: - Entry Points & State Machines

    func refreshEntryPoints() {
        guard !selectedPaths.isEmpty else {
            availableEntryPoints = []
            return
        }
        availableEntryPoints = sequenceGenerator.findEntryPoints(for: selectedPaths)
    }

    func refreshStateMachines() {
        guard !selectedPaths.isEmpty else {
            availableStateMachines = []
            return
        }
        availableStateMachines = stateGenerator.findCandidates(for: selectedPaths)
        let identifiers = availableStateMachines.map(\.identifier)
        if !identifiers.contains(stateIdentifier) {
            stateIdentifier = identifiers.first ?? ""
        }
    }
}
