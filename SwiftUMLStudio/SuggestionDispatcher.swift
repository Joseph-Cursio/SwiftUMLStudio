import Foundation
import SwiftUMLBridgeFramework

/// Pure logic shared by every `handleSuggestion` dispatcher.
///
/// Extracted from `DetailPaneViews`, `ExplorerSidebar`, and `ExplorerDetailView`
/// so the Pro-gate mapping and ViewModel mutation paths can be unit-tested once.
enum SuggestionDispatcher {

    /// The Pro feature that gates `action`, or `nil` when its diagram is free: the entitlement of
    /// the mode it opens. This used to be a second mode-to-feature table, which had to return
    /// something for `.classDiagram` and returned `.sequenceDiagrams`, so a class-diagram
    /// suggestion marked `requiresPro` would have asked a free user to pay for sequence
    /// diagrams (#209).
    nonisolated static func featureRequired(for action: SuggestionAction) -> ProFeature? {
        action.diagramMode.requiredFeature
    }

    /// Apply a suggestion's action to the view model. Callers are responsible
    /// for the feature-gate check before invoking this.
    @MainActor
    static func apply(_ suggestion: DiagramSuggestion, to viewModel: DiagramViewModel) {
        viewModel.diagramMode = suggestion.action.diagramMode
        switch suggestion.action {
        case .sequenceDiagram(let entryPoint), .activityDiagram(let entryPoint):
            viewModel.entryPoint = entryPoint
        case .dependencyGraph(let mode):
            viewModel.depsMode = mode
        case .stateMachine(let identifier):
            viewModel.refreshStateMachines()
            viewModel.stateIdentifier = identifier
        case .classDiagram, .erDiagram, .componentDiagram:
            break
        }
    }
}
