//  Unit tests for DiagramViewModel history operations: save, load, delete, and edge cases.

import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Bookmark restoration

@Suite("DiagramViewModel History — Bookmark Restoration") @MainActor
struct DiagramViewModelBookmarkRestorationTests {

    @Test("loadDiagram restores paths from security-scoped bookmarks when present")
    func loadDiagramResolvesBookmarks() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SUS-load-bookmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmark = try #require(SecurityScopedURL.makeBookmark(for: directory))

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.paths = try JSONEncoder().encode(["/tmp/stale-fallback"])
        entity.pathBookmarks = try JSONEncoder().encode([Data?.some(bookmark)])

        viewModel.loadDiagram(entity)

        // Path comparison via standardized URLs: macOS resolves `/var` to
        // `/private/var`, so the literal strings may differ even when both
        // point at the same on-disk location.
        #expect(viewModel.selectedPaths.count == 1)
        let restoredURL = URL(fileURLWithPath: viewModel.selectedPaths[0])
        #expect(restoredURL.standardizedFileURL == directory.standardizedFileURL)
        #expect(viewModel.selectedPathBookmarks.count == 1)
        #expect(viewModel.selectedPathBookmarks.first == bookmark)
    }

    @Test("loadDiagram falls back to raw paths when bookmark resolution fails")
    func loadDiagramFallsBackOnGarbageBookmark() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.paths = try JSONEncoder().encode(["/tmp/Foo.swift"])
        entity.pathBookmarks = try JSONEncoder().encode([Data?.some(Data([0xDE, 0xAD]))])

        viewModel.loadDiagram(entity)

        #expect(viewModel.selectedPaths == ["/tmp/Foo.swift"])
        #expect(viewModel.selectedPathBookmarks == [nil])
    }

    @Test("loadDiagram on legacy paths-only entity leaves bookmarks empty")
    func loadDiagramLegacyEntity() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)

        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.paths = try JSONEncoder().encode(["/legacy/path"])
        // No pathBookmarks set.

        viewModel.loadDiagram(entity)

        #expect(viewModel.selectedPaths == ["/legacy/path"])
        #expect(viewModel.selectedPathBookmarks.isEmpty)
    }
}
