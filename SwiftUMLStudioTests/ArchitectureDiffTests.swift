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
