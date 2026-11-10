import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing
import ViewInspector

@Suite("MarkupView")
@MainActor
struct MarkupViewTests {

    @Test("empty state is shown when no diagram has been generated")
    func emptyState() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        let view = MarkupView(viewModel: viewModel)
        // ContentUnavailableView has a title we can find by text lookup.
        let strings = try view.inspect()
            .findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("No diagram generated"))
    }

    @Test("TextEditor renders when a diagram script exists")
    func rendersTextEditor() throws {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        // Populate a script via generation fallback — restore from a DiagramEntity
        // which sets currentScript to a SimpleDiagramScript.
        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.scriptText = "@startuml\nclass Foo\n@enduml"
        entity.paths = try JSONEncoder().encode(["/tmp/Foo.swift"])
        viewModel.loadDiagram(entity)

        let view = MarkupView(viewModel: viewModel)
        #expect((try? view.inspect().find(ViewType.TextEditor.self)) != nil)
    }
}
