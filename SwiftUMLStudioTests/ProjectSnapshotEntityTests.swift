import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

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
