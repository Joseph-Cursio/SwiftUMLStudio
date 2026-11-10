import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - Helpers

// MARK: - Pure Pro-feature mapping

@Suite("SuggestionDispatcher.featureRequired") @MainActor
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

    /// Class diagrams are free, so a class-diagram suggestion marked `requiresPro` must not ask
    /// a free user to pay for another diagram's feature (#209).
    @Test("class diagram needs no feature")
    func classDiagramMapping() {
        #expect(SuggestionDispatcher.featureRequired(for: .classDiagram) == nil)
    }

    /// The gate is read from the mode the action opens, so the suggestion and the mode's own
    /// gate in `ContentView` cannot disagree.
    @Test("each action opens its mode and needs that mode's feature", arguments: [
        (SuggestionAction.classDiagram, DiagramMode.classDiagram),
        (.sequenceDiagram(entryPoint: "F.b"), .sequenceDiagram),
        (.dependencyGraph(mode: .modules), .dependencyGraph),
        (.stateMachine(identifier: "H.E"), .stateMachine),
        (.activityDiagram(entryPoint: "F.m"), .activityDiagram),
        (.erDiagram, .erDiagram),
        (.componentDiagram, .componentDiagram),
    ])
    func actionMatchesMode(action: SuggestionAction, mode: DiagramMode) {
        #expect(action.diagramMode == mode)
        #expect(SuggestionDispatcher.featureRequired(for: action) == mode.requiredFeature)
    }

    /// These two must map to their own gates, not to a fallback — ContentView
    /// gates the modes themselves on `.erDiagrams` / `.componentDiagrams`, so a
    /// mismatch would let a suggestion through the paywall only for the mode to
    /// refuse to render.
    @Test("ER action maps to .erDiagrams")
    func erMapping() {
        #expect(SuggestionDispatcher.featureRequired(for: .erDiagram) == .erDiagrams)
    }

    @Test("component action maps to .componentDiagrams")
    func componentMapping() {
        #expect(SuggestionDispatcher.featureRequired(for: .componentDiagram) == .componentDiagrams)
    }

    /// Activity shares its entry point with sequence but not its gate.
    @Test("activity action maps to .activityDiagrams, not .sequenceDiagrams")
    func activityMapping() {
        let feature = SuggestionDispatcher.featureRequired(for: .activityDiagram(entryPoint: "F.m"))
        #expect(feature == .activityDiagrams)
    }
}
