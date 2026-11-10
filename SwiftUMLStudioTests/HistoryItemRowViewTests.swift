import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing
import ViewInspector

private func makeEntity(
    name: String? = "MyProject",
    mode: String? = DiagramMode.classDiagram.rawValue,
    entryPoint: String? = nil,
    timestamp: Date? = Date()
) -> DiagramEntity {
    let entity = DiagramEntity()
    entity.identifier = UUID()
    entity.name = name
    entity.mode = mode
    entity.format = DiagramFormat.plantuml.rawValue
    entity.entryPoint = entryPoint
    entity.timestamp = timestamp
    return entity
}

@Suite("HistoryItemRow — body")
@MainActor
struct HistoryItemRowViewTests {

    @Test("shows the entity name as the headline")
    func rendersName() throws {
        let view = HistoryItemRow(item: makeEntity(name: "MyProject"))
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("MyProject"))
    }

    @Test("nil name falls back to \"Untitled Diagram\"")
    func nilNameFallback() throws {
        let view = HistoryItemRow(item: makeEntity(name: nil))
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("Untitled Diagram"))
    }

    @Test("includes the display-mode label in the detail row")
    func rendersDisplayMode() throws {
        let view = HistoryItemRow(item: makeEntity(
            mode: DiagramMode.sequenceDiagram.rawValue,
            entryPoint: "Foo.bar"
        ))
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("Sequence Diagram (Foo.bar)"))
    }

    @Test("renders the bullet separator text")
    func bulletSeparator() throws {
        let view = HistoryItemRow(item: makeEntity())
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("•"))
    }

    @Test("omits the timestamp text when the entity has no date")
    func nilTimestamp() throws {
        let view = HistoryItemRow(item: makeEntity(timestamp: nil))
        // Only the three Text views above (name, mode, bullet) should exist —
        // the timestamp Text is guarded by an optional binding.
        let texts = try view.inspect().findAll(ViewType.Text.self)
        #expect(texts.count == 3)
    }
}
