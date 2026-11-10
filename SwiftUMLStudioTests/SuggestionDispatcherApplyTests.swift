import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Apply mutates the view model correctly

@Suite("SuggestionDispatcher.apply") @MainActor
struct SuggestionDispatcherApplyTests {

    private func makeSuggestion(_ action: SuggestionAction) -> DiagramSuggestion {
        DiagramSuggestion(
            icon: "", title: "t", description: "d", action: action, requiresPro: false
        )
    }

    @Test("class diagram selects class mode")
    func applyClassDiagram() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(makeSuggestion(.classDiagram), to: viewModel)
        #expect(viewModel.diagramMode == .classDiagram)
    }

    @Test("sequence diagram sets entry point")
    func applySequenceDiagram() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(
            makeSuggestion(.sequenceDiagram(entryPoint: "Foo.bar")),
            to: viewModel
        )
        #expect(viewModel.diagramMode == .sequenceDiagram)
        #expect(viewModel.entryPoint == "Foo.bar")
    }

    @Test("dependency graph sets deps mode")
    func applyDependencyGraph() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(
            makeSuggestion(.dependencyGraph(mode: .modules)),
            to: viewModel
        )
        #expect(viewModel.diagramMode == .dependencyGraph)
        #expect(viewModel.depsMode == .modules)
    }

    @Test("state machine sets identifier (refresh yields empty when no paths)")
    func applyStateMachine() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(
            makeSuggestion(.stateMachine(identifier: "TrafficLight.Light")),
            to: viewModel
        )
        #expect(viewModel.diagramMode == .stateMachine)
        #expect(viewModel.stateIdentifier == "TrafficLight.Light")
    }

    @Test("ER diagram selects ER mode")
    func applyERDiagram() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(makeSuggestion(.erDiagram), to: viewModel)
        #expect(viewModel.diagramMode == .erDiagram)
    }

    @Test("activity diagram selects activity mode and carries the entry point")
    func applyActivityDiagram() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(
            makeSuggestion(.activityDiagram(entryPoint: "Loader.load")),
            to: viewModel
        )
        #expect(viewModel.diagramMode == .activityDiagram)
        #expect(viewModel.entryPoint == "Loader.load")
    }

    @Test("component diagram selects component mode")
    func applyComponentDiagram() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        SuggestionDispatcher.apply(makeSuggestion(.componentDiagram), to: viewModel)
        #expect(viewModel.diagramMode == .componentDiagram)
    }
}
