import Foundation
import SwiftData
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

private func runOnMain(_ block: @MainActor () throws -> Void) throws {
    if Thread.isMainThread {
        try MainActor.assumeIsolated(block)
    } else {
        var thrownError: (any Error)?
        DispatchQueue.main.sync {
            do { try MainActor.assumeIsolated(block) } catch { thrownError = error }
        }
        if let err = thrownError { throw err }
    }
}

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

@Suite("ProjectSnapshot Entity")
struct ProjectSnapshotEntityTests {

    @Test("ProjectSnapshot can be created and saved")
    func createAndSave() throws {
        try runOnMain {
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
    }

    @Test("ProjectSnapshot decodes type breakdown from JSON")
    func decodedTypeBreakdown() throws {
        try runOnMain {
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
    }

    @Test("ProjectSnapshot decodes top connected types from JSON")
    func decodedTopConnectedTypes() throws {
        try runOnMain {
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
    }

    @Test("ProjectSnapshot decodes project paths from JSON")
    func decodedProjectPaths() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let snapshot = ProjectSnapshot()
            snapshot.identifier = UUID()
            snapshot.projectPaths = try JSONEncoder().encode(["/path/one", "/path/two"])
            modelContext.insert(snapshot)

            let paths = snapshot.decodedProjectPaths
            #expect(paths == ["/path/one", "/path/two"])
        }
    }

    @Test("ProjectSnapshot returns empty collections for nil data")
    func nilDataReturnsEmpty() {
        runOnMain {
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
    }

    @Test("ProjectSnapshot decodes path bookmarks with optional entries")
    func decodedPathBookmarks() throws {
        try runOnMain {
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
}

// MARK: - SnapshotManager Tests

@Suite("SnapshotManager")
struct SnapshotManagerTests {

    @Test("saveSnapshot creates a ProjectSnapshot from summary")
    func saveSnapshot() throws {
        try runOnMain {
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
    }

    @Test("fetchSnapshots returns snapshots newest first")
    func fetchSnapshotsOrder() throws {
        try runOnMain {
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
    }

    @Test("latestSnapshot finds matching snapshot by paths")
    func latestSnapshotByPaths() throws {
        try runOnMain {
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
    }

    @Test("latestSnapshot returns nil when no matching paths")
    func latestSnapshotNoMatch() {
        runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let result = SnapshotManager.latestSnapshot(for: ["/nonexistent"], modelContext: modelContext)
            #expect(result == nil)
        }
    }

    @Test("saveSnapshot persists path bookmarks alongside paths")
    func saveSnapshotPersistsBookmarks() throws {
        try runOnMain {
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
    }

    @Test("saveSnapshot leaves bookmarks nil when no bookmarks provided")
    func saveSnapshotNoBookmarks() throws {
        try runOnMain {
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
    }

    @Test("deleteSnapshot removes snapshot from store")
    func deleteSnapshot() throws {
        try runOnMain {
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
}
