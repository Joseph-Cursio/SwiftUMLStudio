//
//  DiagramViewModelHistoryFormatTests.swift
//  SwiftUMLStudioTests
//
//  Save/load round trips for diagrams whose script is written in a different language from the
//  one the Format picker asked for. The picker restores to the user's choice; the script keeps
//  the format of its text, which is what the preview and Export pick their renderer from.
//

import Foundation
import SwiftData
import Testing
@testable import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramViewModel History — Fallback Formats") @MainActor
struct DiagramViewModelHistoryFormatTests {

    private func configuration(_ format: DiagramFormat) -> Configuration {
        var config = Configuration.default
        config.format = format
        return config
    }

    /// Saves `viewModel`'s current script, then restores the entry into a fresh view model over the
    /// same store, so nothing reaches the restored side except what was persisted.
    private func roundTrip(
        _ viewModel: DiagramViewModel,
        in persistence: PersistenceController
    ) throws -> DiagramViewModel {
        viewModel.saveToHistory()
        let restored = DiagramViewModel(persistenceController: persistence)
        restored.loadHistory()
        restored.loadDiagram(try #require(restored.history.first))
        return restored
    }

    @Test("state diagram saved in SVG restores the picker to SVG and the script as Mermaid")
    func stateDiagramInSVG() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.diagramMode = .stateMachine
        viewModel.diagramFormat = .svg
        let model = StateMachineModel(
            hostType: "TrafficLight", enumType: "Light",
            states: [StateMachineState(name: "red", isInitial: true), StateMachineState(name: "green")],
            transitions: [StateTransition(from: "red", toState: "green", trigger: "advance")]
        )
        let saved = StateScript(model: model, configuration: configuration(.svg))
        viewModel.stateScript = saved
        // There is no native SVG layout for state diagrams, so the Bridge emits Mermaid.
        #expect(saved.format == .mermaid)

        let restored = try roundTrip(viewModel, in: persistence)

        #expect(restored.diagramFormat == .svg)
        #expect(restored.currentScript?.format == .mermaid)
        #expect(restored.currentScript?.text == saved.text)
    }

    @Test("sequence diagram saved in Nomnoml restores the picker to Nomnoml and the script as Mermaid")
    func sequenceDiagramInNomnoml() throws {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .nomnoml
        viewModel.entryPoint = "Foo.bar"
        let edges = [CallEdge(
            callerType: "Foo", callerMethod: "bar",
            calleeType: "Baz", calleeMethod: "qux",
            isAsync: false, isUnresolved: false
        )]
        // Nomnoml has no sequence syntax, so the Bridge emits Mermaid for it. The script is built
        // from a Mermaid configuration so this test covers what history persists, not how the
        // Bridge reports its fallback — the Bridge's own tests cover that.
        let saved = SequenceScript(
            traversedEdges: edges, entryType: "Foo", entryMethod: "bar",
            configuration: configuration(.mermaid)
        )
        viewModel.sequenceScript = saved

        let restored = try roundTrip(viewModel, in: persistence)

        #expect(restored.diagramFormat == .nomnoml)
        #expect(restored.entryPoint == "Foo.bar")
        #expect(restored.currentScript?.format == .mermaid)
        #expect(restored.currentScript?.text == saved.text)
    }

    @Test("entity saved before the script format was recorded restores the script in the picker's format")
    func legacyEntityFallsBackToPickerFormat() {
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)

        let entity = DiagramEntity()
        entity.timestamp = Date()
        entity.mode = DiagramMode.classDiagram.rawValue
        entity.format = DiagramFormat.mermaid.rawValue
        entity.scriptText = "classDiagram\nclass Foo"
        persistence.container.mainContext.insert(entity)

        viewModel.loadDiagram(entity)

        #expect(entity.scriptFormat == nil)
        #expect(viewModel.diagramFormat == .mermaid)
        #expect(viewModel.currentScript?.format == .mermaid)
    }
}
