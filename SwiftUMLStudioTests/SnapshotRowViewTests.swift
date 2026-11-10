import Foundation
@testable import SwiftUMLStudio
import Testing
import ViewInspector

private func makeSnapshot(
    typeCount: Int = 10,
    relationshipCount: Int = 20,
    moduleCount: Int = 3,
    timestamp: Date? = Date().addingTimeInterval(-3_600)
) -> ProjectSnapshot {
    ProjectSnapshot(
        identifier: UUID(),
        timestamp: timestamp,
        typeCount: typeCount,
        relationshipCount: relationshipCount,
        moduleCount: moduleCount,
        fileCount: 5
    )
}

@Suite("SnapshotRowView")
@MainActor
struct SnapshotRowViewTests {

    @Test("shows type / relationship / module counts")
    func rendersCounts() throws {
        let view = SnapshotRowView(snapshot: makeSnapshot(
            typeCount: 12, relationshipCount: 7, moduleCount: 4
        ))
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("12 types"))
        #expect(strings.contains("7 rels"))
        #expect(strings.contains("4 mods"))
    }

    @Test("nil timestamp falls back to \"Unknown\"")
    func unknownTimestamp() throws {
        let view = SnapshotRowView(snapshot: makeSnapshot(timestamp: nil))
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("Unknown"))
    }

    @Test("includes camera icon")
    func rendersCameraIcon() throws {
        let view = SnapshotRowView(snapshot: makeSnapshot())
        let images = try view.inspect().findAll(ViewType.Image.self)
        let names = images.compactMap { try? $0.actualImage().name() }
        #expect(names.contains("camera.fill"))
    }
}
