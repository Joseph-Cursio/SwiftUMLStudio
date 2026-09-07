import Foundation
import SwiftData
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Test Helpers

private func makeTestSummary(
    totalFiles: Int = 10,
    totalTypes: Int = 5,
    typeBreakdown: [String: Int] = ["Classes": 3, "Structs": 2],
    totalRelationships: Int = 8,
    moduleImports: [String] = ["Foundation", "UIKit"],
    topConnectedTypes: [(name: String, connectionCount: Int)] = [
        (name: "ViewModel", connectionCount: 4),
        (name: "Service", connectionCount: 3)
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

// MARK: - ProjectSnapshot Entity Tests

@Suite("ProjectSnapshot Entity") @MainActor
struct ProjectSnapshotEntityTests {

    @Test("ProjectSnapshot can be created and saved")
    func createAndSave() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        snapshot.timestamp = Date()
        snapshot.typeCount = 10
        snapshot.relationshipCount = 5
        snapshot.moduleCount = 3
        snapshot.fileCount = 20
        modelContext.insert(snapshot)

        try modelContext.save()

        let descriptor = FetchDescriptor<ProjectSnapshot>()
        let results = try modelContext.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.typeCount == 10)
        #expect(results.first?.relationshipCount == 5)
        #expect(results.first?.moduleCount == 3)
        #expect(results.first?.fileCount == 20)
    }

    @Test("ProjectSnapshot decodes type breakdown from JSON")
    func decodedTypeBreakdown() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        snapshot.typeBreakdown = try JSONEncoder().encode(["Classes": 3, "Structs": 2])
        modelContext.insert(snapshot)

        let breakdown = snapshot.decodedTypeBreakdown
        #expect(breakdown["Classes"] == 3)
        #expect(breakdown["Structs"] == 2)
    }

    @Test("ProjectSnapshot decodes top connected types from JSON")
    func decodedTopConnectedTypes() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        let encoded: [[String: Int]] = [["ViewModel": 4], ["Service": 3]]
        snapshot.topConnectedTypes = try JSONEncoder().encode(encoded)
        modelContext.insert(snapshot)

        let decoded = snapshot.decodedTopConnectedTypes
        #expect(decoded.count == 2)
        #expect(decoded.first?.name == "ViewModel")
        #expect(decoded.first?.connectionCount == 4)
    }

    @Test("ProjectSnapshot decodes project paths from JSON")
    func decodedProjectPaths() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        snapshot.projectPaths = try JSONEncoder().encode(["/path/one", "/path/two"])
        modelContext.insert(snapshot)

        let paths = snapshot.decodedProjectPaths
        #expect(paths == ["/path/one", "/path/two"])
    }

    @Test("ProjectSnapshot returns empty collections for nil data")
    func nilDataReturnsEmpty() {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        modelContext.insert(snapshot)

        #expect(snapshot.decodedTypeBreakdown.isEmpty)
        #expect(snapshot.decodedTopConnectedTypes.isEmpty)
        #expect(snapshot.decodedProjectPaths.isEmpty)
        #expect(snapshot.decodedProjectPathBookmarks.isEmpty)
    }

    @Test("ProjectSnapshot decodes path bookmarks with optional entries")
    func decodedPathBookmarks() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext

        let snapshot = ProjectSnapshot()
        snapshot.identifier = UUID()
        let bookmarks: [Data?] = [Data([0x01, 0x02]), nil, Data([0x03])]
        snapshot.projectPathBookmarks = try JSONEncoder().encode(bookmarks)
        modelContext.insert(snapshot)

        let decoded = snapshot.decodedProjectPathBookmarks
        #expect(decoded.count == 3)
        #expect(decoded[0] == Data([0x01, 0x02]))
        #expect(decoded[1] == nil)
        #expect(decoded[2] == Data([0x03]))
    }
}

// MARK: - SnapshotManager Tests

@Suite("SnapshotManager") @MainActor
struct SnapshotManagerTests {

    @Test("saveSnapshot creates a ProjectSnapshot from summary")
    func saveSnapshot() throws {
        let controller = PersistenceController(inMemory: true)
        let modelContext = controller.container.mainContext
        let summary = makeTestSummary()

        SnapshotManager.saveSnapshot(from: summary, paths: ["/test/path"], modelContext: modelContext)

        let descriptor = FetchDescriptor<ProjectSnapshot>()
        let results = try modelContext.fetch(descriptor)
        #expect(results.count == 1)

        let snapshot = results.first!
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
        SnapshotManager.saveSnapshot(from: summary, paths: targetPaths, modelContext: modelContext)

        // Save snapshot with different paths
        SnapshotManager.saveSnapshot(from: summary, paths: ["/other/path"], modelContext: modelContext)

        let latest = SnapshotManager.latestSnapshot(for: targetPaths, modelContext: modelContext)
        #expect(latest != nil)
        #expect(Set(latest!.decodedProjectPaths) == Set(targetPaths))
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
        SnapshotManager.saveSnapshot(
            from: newer,
            paths: targetPaths,
            at: Date(timeIntervalSince1970: 2_000),
            modelContext: modelContext
        )
        SnapshotManager.saveSnapshot(
            from: older,
            paths: targetPaths,
            at: Date(timeIntervalSince1970: 1_000),
            modelContext: modelContext
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

        SnapshotManager.saveSnapshot(
            from: summary,
            paths: ["/one", "/two"],
            bookmarks: bookmarks,
            modelContext: modelContext
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

        SnapshotManager.saveSnapshot(
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
        SnapshotManager.saveSnapshot(from: summary, paths: ["/test"], modelContext: modelContext)

        let snapshots = SnapshotManager.fetchSnapshots(modelContext: modelContext)
        #expect(snapshots.count == 1)

        SnapshotManager.deleteSnapshot(snapshots.first!, modelContext: modelContext)

        let remaining = SnapshotManager.fetchSnapshots(modelContext: modelContext)
        #expect(remaining.isEmpty)
    }
}
