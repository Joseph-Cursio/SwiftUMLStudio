import Foundation
import SwiftUMLBridgeFramework

/// Pure logic shared by every `handleSuggestion` dispatcher.
///
/// Extracted from `DetailPaneViews`, `ExplorerSidebar`, and `ExplorerDetailView`
/// so the Pro-gate mapping and ViewModel mutation paths can be unit-tested once.
enum SuggestionDispatcher {

    /// Maps a suggestion action to the Pro feature that gates it.
    ///
    /// Class diagrams are never Pro-gated at the feature level, but the picker
    /// reuses `.sequenceDiagrams` as a benign fallback since `SuggestionAction`
    /// is exhaustively switched in each dispatcher.
    nonisolated static func featureRequired(for action: SuggestionAction) -> ProFeature {
        switch action {
        case .sequenceDiagram: return .sequenceDiagrams
        case .dependencyGraph: return .dependencyGraphs
        case .stateMachine: return .stateMachines
        case .classDiagram: return .sequenceDiagrams
        }
    }

    /// Apply a suggestion's action to the view model. Callers are responsible
    /// for the feature-gate check before invoking this.
    @MainActor
    static func apply(_ suggestion: DiagramSuggestion, to viewModel: DiagramViewModel) {
        switch suggestion.action {
        case .classDiagram:
            viewModel.diagramMode = .classDiagram
        case .sequenceDiagram(let entryPoint):
            viewModel.diagramMode = .sequenceDiagram
            viewModel.entryPoint = entryPoint
        case .dependencyGraph(let mode):
            viewModel.diagramMode = .dependencyGraph
            viewModel.depsMode = mode
        case .stateMachine(let identifier):
            viewModel.diagramMode = .stateMachine
            viewModel.refreshStateMachines()
            viewModel.stateIdentifier = identifier
        }
    }
}
