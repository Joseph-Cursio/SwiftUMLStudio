import Foundation
import SwiftData

/// Represents the difference between a current project state and a previous snapshot.
struct ArchitectureDiff {
    let previousTimestamp: Date
    let typeDelta: Int
    let relationshipDelta: Int
    let moduleDelta: Int
    let fileDelta: Int
    let typeBreakdownDeltas: [String: Int]
    let complexityChanges: [(name: String, delta: Int)]
}

/// Manages saving and retrieving ProjectSnapshot records for architecture change tracking.
@MainActor
enum SnapshotManager {

    /// Save a snapshot from the current project summary.
    static func saveSnapshot(
        from summary: ProjectSummary,
        paths: [String],
        modelContext: ModelContext
    ) {
        let snapshot = ProjectSnapshot(
            identifier: UUID(),
            timestamp: Date(),
            typeCount: summary.totalTypes,
            relationshipCount: summary.totalRelationships,
            moduleCount: summary.moduleImports.count,
            fileCount: summary.totalFiles,
            typeBreakdown: try? JSONEncoder().encode(summary.typeBreakdown),
            topConnectedTypes: try? JSONEncoder().encode(
                summary.topConnectedTypes.map { ["\($0.name)": $0.connectionCount] }
            ),
            projectPaths: try? JSONEncoder().encode(paths)
        )
        modelContext.insert(snapshot)
        try? modelContext.save()
    }

    /// Fetch all snapshots, newest first.
    static func fetchSnapshots(modelContext: ModelContext) -> [ProjectSnapshot] {
        let descriptor = FetchDescriptor<ProjectSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch the most recent snapshot for a given set of paths.
    static func latestSnapshot(
        for paths: [String],
        modelContext: ModelContext
    ) -> ProjectSnapshot? {
        let snapshots = fetchSnapshots(modelContext: modelContext)
        let pathSet = Set(paths)
        return snapshots.first { snapshot in
            Set(snapshot.decodedProjectPaths) == pathSet
        }
    }

    /// Compute the diff between the current summary and a previous snapshot.
    static func computeDiff(
        current summary: ProjectSummary,
        previous snapshot: ProjectSnapshot
    ) -> ArchitectureDiff {
        let typeDelta = summary.totalTypes - snapshot.typeCount
        let relationshipDelta = summary.totalRelationships - snapshot.relationshipCount
        let moduleDelta = summary.moduleImports.count - snapshot.moduleCount
        let fileDelta = summary.totalFiles - snapshot.fileCount

        let previousBreakdown = snapshot.decodedTypeBreakdown
        var breakdownDeltas: [String: Int] = [:]
        let allKeys = Set(summary.typeBreakdown.keys).union(previousBreakdown.keys)
        for key in allKeys {
            let current = summary.typeBreakdown[key] ?? 0
            let previous = previousBreakdown[key] ?? 0
            let delta = current - previous
            if delta != 0 {
                breakdownDeltas[key] = delta
            }
        }

        let previousTopTypes = snapshot.decodedTopConnectedTypes
        let previousByName = Dictionary(
            previousTopTypes.map { ($0.name, $0.connectionCount) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentByName = Dictionary(
            summary.topConnectedTypes.map { ($0.name, $0.connectionCount) },
            uniquingKeysWith: { first, _ in first }
        )
        let allTypeNames = Set(previousByName.keys).union(currentByName.keys)
        let complexityChanges: [(name: String, delta: Int)] = allTypeNames.compactMap { name in
            let current = currentByName[name] ?? 0
            let previous = previousByName[name] ?? 0
            let delta = current - previous
            guard delta != 0 else { return nil }
            return (name: name, delta: delta)
        }.sorted { abs($0.delta) > abs($1.delta) }

        return ArchitectureDiff(
            previousTimestamp: snapshot.timestamp ?? Date.distantPast,
            typeDelta: typeDelta,
            relationshipDelta: relationshipDelta,
            moduleDelta: moduleDelta,
            fileDelta: fileDelta,
            typeBreakdownDeltas: breakdownDeltas,
            complexityChanges: complexityChanges
        )
    }

    /// Delete a snapshot.
    static func deleteSnapshot(_ snapshot: ProjectSnapshot, modelContext: ModelContext) {
        modelContext.delete(snapshot)
        try? modelContext.save()
    }
}
