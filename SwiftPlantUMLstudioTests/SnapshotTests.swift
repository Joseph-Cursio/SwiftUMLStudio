import Foundation
import SwiftData
import Testing
@testable import SwiftPlantUMLstudio

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
    entryPoints: [String] = ["App.main"]
) -> ProjectSummary {
    ProjectSummary(
        totalFiles: totalFiles,
        totalTypes: totalTypes,
        typeBreakdown: typeBreakdown,
        totalRelationships: totalRelationships,
        moduleImports: moduleImports,
        topConnectedTypes: topConnectedTypes,
        cycleWarnings: cycleWarnings,
        entryPoints: entryPoints
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

// MARK: - ArchitectureDiff Computation Tests

@Suite("ArchitectureDiff Computation")
struct ArchitectureDiffTests {

    @Test("computeDiff calculates correct deltas for growth")
    func diffWithGrowth() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            // Previous state: 5 types, 8 relationships, 2 modules, 10 files
            let previousSummary = makeTestSummary()
            SnapshotManager.saveSnapshot(from: previousSummary, paths: ["/test"], modelContext: modelContext)
            let snapshot = SnapshotManager.fetchSnapshots(modelContext: modelContext).first!

            // Current state: 8 types, 15 relationships, 3 modules, 14 files
            let currentSummary = makeTestSummary(
                totalFiles: 14,
                totalTypes: 8,
                typeBreakdown: ["Classes": 5, "Structs": 3],
                totalRelationships: 15,
                moduleImports: ["Foundation", "UIKit", "SwiftUI"]
            )

            let diff = SnapshotManager.computeDiff(current: currentSummary, previous: snapshot)

            #expect(diff.typeDelta == 3)
            #expect(diff.relationshipDelta == 7)
            #expect(diff.moduleDelta == 1)
            #expect(diff.fileDelta == 4)
        }
    }

    @Test("computeDiff calculates correct deltas for shrinkage")
    func diffWithShrinkage() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let previousSummary = makeTestSummary(totalTypes: 10, totalRelationships: 20)
            SnapshotManager.saveSnapshot(from: previousSummary, paths: ["/test"], modelContext: modelContext)
            let snapshot = SnapshotManager.fetchSnapshots(modelContext: modelContext).first!

            let currentSummary = makeTestSummary(totalTypes: 7, totalRelationships: 12)
            let diff = SnapshotManager.computeDiff(current: currentSummary, previous: snapshot)

            #expect(diff.typeDelta == -3)
            #expect(diff.relationshipDelta == -8)
        }
    }

    @Test("computeDiff detects type breakdown changes")
    func diffTypeBreakdownChanges() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let previousSummary = makeTestSummary(typeBreakdown: ["Classes": 3, "Structs": 2])
            SnapshotManager.saveSnapshot(from: previousSummary, paths: ["/test"], modelContext: modelContext)
            let snapshot = SnapshotManager.fetchSnapshots(modelContext: modelContext).first!

            let currentSummary = makeTestSummary(
                typeBreakdown: ["Classes": 5, "Structs": 2, "Enums": 1]
            )
            let diff = SnapshotManager.computeDiff(current: currentSummary, previous: snapshot)

            #expect(diff.typeBreakdownDeltas["Classes"] == 2)
            #expect(diff.typeBreakdownDeltas["Structs"] == nil) // no change
            #expect(diff.typeBreakdownDeltas["Enums"] == 1) // new
        }
    }

    @Test("computeDiff detects complexity changes in top connected types")
    func diffComplexityChanges() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let previousSummary = makeTestSummary(
                topConnectedTypes: [(name: "ViewModel", connectionCount: 4)]
            )
            SnapshotManager.saveSnapshot(from: previousSummary, paths: ["/test"], modelContext: modelContext)
            let snapshot = SnapshotManager.fetchSnapshots(modelContext: modelContext).first!

            let currentSummary = makeTestSummary(
                topConnectedTypes: [(name: "ViewModel", connectionCount: 7)]
            )
            let diff = SnapshotManager.computeDiff(current: currentSummary, previous: snapshot)

            let viewModelChange = diff.complexityChanges.first { $0.name == "ViewModel" }
            #expect(viewModelChange?.delta == 3)
        }
    }

    @Test("computeDiff returns zero deltas when nothing changed")
    func diffNoChanges() throws {
        try runOnMain {
            let controller = PersistenceController(inMemory: true)
            let modelContext = controller.container.mainContext

            let summary = makeTestSummary()
            SnapshotManager.saveSnapshot(from: summary, paths: ["/test"], modelContext: modelContext)
            let snapshot = SnapshotManager.fetchSnapshots(modelContext: modelContext).first!

            let diff = SnapshotManager.computeDiff(current: summary, previous: snapshot)

            #expect(diff.typeDelta == 0)
            #expect(diff.relationshipDelta == 0)
            #expect(diff.moduleDelta == 0)
            #expect(diff.fileDelta == 0)
            #expect(diff.typeBreakdownDeltas.isEmpty)
            #expect(diff.complexityChanges.isEmpty)
        }
    }
}
