import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

// MARK: - Pure Pro-feature mapping

@Suite("SuggestionDispatcher.featureRequired")
struct SuggestionDispatcherFeatureMappingTests {

    @Test("sequence action maps to .sequenceDiagrams")
    func sequenceMapping() {
        let feature = SuggestionDispatcher.featureRequired(for: .sequenceDiagram(entryPoint: "F.b"))
        #expect(feature == .sequenceDiagrams)
    }

    @Test("dependency action maps to .dependencyGraphs")
    func dependencyMapping() {
        let feature = SuggestionDispatcher.featureRequired(for: .dependencyGraph(mode: .types))
        #expect(feature == .dependencyGraphs)
    }

    @Test("state machine action maps to .stateMachines")
    func stateMachineMapping() {
        let feature = SuggestionDispatcher.featureRequired(for: .stateMachine(identifier: "H.E"))
        #expect(feature == .stateMachines)
    }

    @Test("class diagram falls back to .sequenceDiagrams")
    func classDiagramMapping() {
        // Not Pro-gated in practice, but the dispatcher must return a value
        // to satisfy the exhaustive switch on every call site.
        let feature = SuggestionDispatcher.featureRequired(for: .classDiagram)
        #expect(feature == .sequenceDiagrams)
    }
}

// MARK: - Apply mutates the view model correctly

@Suite("SuggestionDispatcher.apply")
struct SuggestionDispatcherApplyTests {

    private func makeSuggestion(_ action: SuggestionAction) -> DiagramSuggestion {
        DiagramSuggestion(
            icon: "", title: "t", description: "d", action: action, requiresPro: false
        )
    }

    @Test("class diagram selects class mode")
    func applyClassDiagram() {
        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
            SuggestionDispatcher.apply(makeSuggestion(.classDiagram), to: viewModel)
            #expect(viewModel.diagramMode == .classDiagram)
        }
    }

    @Test("sequence diagram sets entry point")
    func applySequenceDiagram() {
        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
            SuggestionDispatcher.apply(
                makeSuggestion(.sequenceDiagram(entryPoint: "Foo.bar")),
                to: viewModel
            )
            #expect(viewModel.diagramMode == .sequenceDiagram)
            #expect(viewModel.entryPoint == "Foo.bar")
        }
    }

    @Test("dependency graph sets deps mode")
    func applyDependencyGraph() {
        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
            SuggestionDispatcher.apply(
                makeSuggestion(.dependencyGraph(mode: .modules)),
                to: viewModel
            )
            #expect(viewModel.diagramMode == .dependencyGraph)
            #expect(viewModel.depsMode == .modules)
        }
    }

    @Test("state machine sets identifier (refresh yields empty when no paths)")
    func applyStateMachine() {
        runOnMain {
            let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
            SuggestionDispatcher.apply(
                makeSuggestion(.stateMachine(identifier: "TrafficLight.Light")),
                to: viewModel
            )
            #expect(viewModel.diagramMode == .stateMachine)
            #expect(viewModel.stateIdentifier == "TrafficLight.Light")
        }
    }
}
