import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Test Helpers

private func makeTestSummary(
    totalFiles: Int = 10,
    totalTypes: Int = 5,
    typeBreakdown: [String: Int] = ["Classes": 3, "Structs": 2],
    totalRelationships: Int = 8,
    moduleImports: [String] = ["Foundation", "UIKit"],
    topConnectedTypes: [(name: String, connectionCount: Int)] = [
        (name: "ViewModel", connectionCount: 4),
        (name: "Service", connectionCount: 3),
    ],
    cycleWarnings: [String] = [],
    entryPoints: [String] = ["App.main"],
    stateMachines: [StateMachineModel] = []
) -> ProjectSummary {
    ProjectSummary(
        totalFiles: totalFiles,
        totalTypes: totalTypes,
        typeBreakdown: typeBreakdown,
        totalRelationships: totalRelationships,
        moduleImports: moduleImports,
        topConnectedTypes: topConnectedTypes,
        cycleWarnings: cycleWarnings,
        entryPoints: entryPoints,
        stateMachines: stateMachines
    )
}

// MARK: - SnapshotManager Tests

@Suite("SnapshotManager") @MainActor
struct SnapshotManagerTests {

    @Test("saveSnapshot creates a ProjectSnapshot from summary")
    func saveSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let summary = makeTestSummary()

        try SnapshotManager.saveSnapshot(from: summary, paths: ["/test/path"], modelContext: modelContext)

        let descriptor = FetchDescriptor<ProjectSnapshot>()
        let results = try modelContext.fetch(descriptor)
        #expect(results.count == 1)

        let snapshot = try #require(results.first)
        #expect(snapshot.typeCount == 5)
        #expect(snapshot.relationshipCount == 8)
        #expect(snapshot.moduleCount == 2)
        #expect(snapshot.fileCount == 10)
        #expect(snapshot.decodedProjectPaths == ["/test/path"])
    }

    @Test("fetchSnapshots returns snapshots newest first")
    func fetchSnapshotsOrder() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        for idx in 0..<3 {
            let snapshot = ProjectSnapshot()
            snapshot.identifier = UUID()
            snapshot.timestamp = Date().addingTimeInterval(TimeInterval(idx * 100))
            snapshot.typeCount = idx
            modelContext.insert(snapshot)
        }
        try modelContext.save()

        let results = SnapshotManager.fetchSnapshots(modelContext: modelContext)
        #expect(results.count == 3)
        #expect(results[0].typeCount == 2) // newest
        #expect(results[2].typeCount == 0) // oldest
    }

    @Test("latestSnapshot finds matching snapshot by paths")
    func latestSnapshotByPaths() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let targetPaths = ["/project/a", "/project/b"]

        // Save snapshot with matching paths
        let summary = makeTestSummary()
        try SnapshotManager.saveSnapshot(from: summary, paths: targetPaths, modelContext: modelContext)

        // Save snapshot with different paths
        try SnapshotManager.saveSnapshot(from: summary, paths: ["/other/path"], modelContext: modelContext)

        let latest = SnapshotManager.latestSnapshot(for: targetPaths, modelContext: modelContext)
        let found = try #require(latest)
        #expect(Set(found.decodedProjectPaths) == Set(targetPaths))
    }

    /// The half of `latestSnapshot`'s name that was not covered.
    ///
    /// The test above saves two snapshots with *different* paths, so it proves the filter and says
    /// nothing about "latest". Two snapshots for the *same* paths could not be written before:
    /// `saveSnapshot` read the clock itself, so a test could not say which was newer, and two
    /// saves landing in one tick would have made the assertion flaky rather than wrong.
    @Test("latestSnapshot returns the newest of several snapshots for the same paths")
    func latestSnapshotPicksTheNewest() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let targetPaths = ["/project/a"]

        let older = makeTestSummary(totalFiles: 10)
        let newer = makeTestSummary(totalFiles: 99)

        // Saved newest-first, so passing the test cannot be an accident of insertion order.
        try SnapshotManager.saveSnapshot(
            from: newer,
            paths: targetPaths,
            modelContext: modelContext,
            at: Date(timeIntervalSince1970: 2_000)
        )
        try SnapshotManager.saveSnapshot(
            from: older,
            paths: targetPaths,
            modelContext: modelContext,
            at: Date(timeIntervalSince1970: 1_000)
        )

        let latest = SnapshotManager.latestSnapshot(for: targetPaths, modelContext: modelContext)
        #expect(latest?.fileCount == 99)
        #expect(latest?.timestamp == Date(timeIntervalSince1970: 2_000))
    }

    @Test("latestSnapshot returns nil when no matching paths")
    func latestSnapshotNoMatch() {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let result = SnapshotManager.latestSnapshot(for: ["/nonexistent"], modelContext: modelContext)
        #expect(result == nil)
    }

    /// One press of Save is one event.
    ///
    /// `save` used to call `saveToHistory` and `saveSnapshot`, each of which read the clock for
    /// itself, so the two records it wrote disagreed about when the user pressed Save. Now it
    /// reads once and hands the instant down.
    @Test("save stamps the history entry and the snapshot with one instant")
    func saveUsesOneInstantForBothRecords() throws {
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext
        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.projectSummary = makeTestSummary()

        // `currentScript` is a computed property; restoring a history entry is how a test gives
        // it one, and `saveToHistory` returns early without it.
        let seed = DiagramEntity()
        seed.timestamp = Date(timeIntervalSince1970: 1)
        seed.mode = DiagramMode.classDiagram.rawValue
        seed.format = DiagramFormat.plantuml.rawValue
        seed.scriptText = "@startuml\nclass Foo\n@enduml"
        modelContext.insert(seed)
        try modelContext.save()
        viewModel.loadDiagram(seed)

        let pressedSave = Date(timeIntervalSince1970: 5_000)
        viewModel.save(isProUnlocked: true, at: pressedSave)

        viewModel.loadHistory()
        viewModel.loadSnapshots()
        #expect(viewModel.history.first?.timestamp == pressedSave)
        #expect(viewModel.snapshots.first?.timestamp == pressedSave)
    }

    @Test("saveSnapshot persists path bookmarks alongside paths")
    func saveSnapshotPersistsBookmarks() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let summary = makeTestSummary()
        let bookmarks: [Data?] = [Data([0xAA, 0xBB]), nil]

        try SnapshotManager.saveSnapshot(
            from: summary,
            paths: ["/one", "/two"],
            modelContext: modelContext,
            bookmarks: bookmarks
        )

        let snapshot = try #require(
            SnapshotManager.fetchSnapshots(modelContext: modelContext).first
        )
        #expect(snapshot.decodedProjectPaths == ["/one", "/two"])
        let decoded = snapshot.decodedProjectPathBookmarks
        #expect(decoded.count == 2)
        #expect(decoded[0] == Data([0xAA, 0xBB]))
        #expect(decoded[1] == nil)
    }

    @Test("saveSnapshot leaves bookmarks nil when no bookmarks provided")
    func saveSnapshotNoBookmarks() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let summary = makeTestSummary()

        try SnapshotManager.saveSnapshot(
            from: summary,
            paths: ["/legacy"],
            modelContext: modelContext
        )

        let snapshot = try #require(
            SnapshotManager.fetchSnapshots(modelContext: modelContext).first
        )
        #expect(snapshot.projectPathBookmarks == nil)
        #expect(snapshot.decodedProjectPathBookmarks.isEmpty)
    }

    @Test("deleteSnapshot removes snapshot from store")
    func deleteSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let summary = makeTestSummary()
        try SnapshotManager.saveSnapshot(from: summary, paths: ["/test"], modelContext: modelContext)

        let snapshots = SnapshotManager.fetchSnapshots(modelContext: modelContext)
        #expect(snapshots.count == 1)

        let snapshot = try #require(snapshots.first)
        try SnapshotManager.deleteSnapshot(snapshot, modelContext: modelContext)

        let remaining = SnapshotManager.fetchSnapshots(modelContext: modelContext)
        #expect(remaining.isEmpty)
    }
}
