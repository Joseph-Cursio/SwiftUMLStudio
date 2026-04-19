import Foundation
import SwiftUMLBridgeFramework

struct DiagramSuggestion: Identifiable, Sendable {
    let identifier = UUID()
    let icon: String
    let title: String
    let description: String
    let action: SuggestionAction
    let requiresPro: Bool

    var id: UUID { identifier }
}

enum SuggestionAction: Sendable {
    case classDiagram
    case sequenceDiagram(entryPoint: String)
    case dependencyGraph(mode: DepsMode)
    case stateMachine(identifier: String)
}

nonisolated enum SuggestionEngine {
    static func generate(from summary: ProjectSummary, isProUnlocked: Bool) -> [DiagramSuggestion] {
        var suggestions: [DiagramSuggestion] = []
        if let classSuggestion = classDiagramSuggestion(from: summary) {
            suggestions.append(classSuggestion)
        }
        suggestions.append(contentsOf: sequenceSuggestions(from: summary))
        suggestions.append(contentsOf: dependencySuggestions(from: summary))
        suggestions.append(contentsOf: stateMachineSuggestions(from: summary))
        return suggestions
    }

    private static func classDiagramSuggestion(from summary: ProjectSummary) -> DiagramSuggestion? {
        guard summary.totalTypes > 0 else { return nil }
        return DiagramSuggestion(
            icon: "rectangle.3.group",
            title: "See how your types are connected",
            description: "\(summary.totalTypes) types with \(summary.totalRelationships) relationships.",
            action: .classDiagram,
            requiresPro: false
        )
    }

    private static func sequenceSuggestions(from summary: ProjectSummary) -> [DiagramSuggestion] {
        summary.entryPoints.prefix(3).map { entryPoint in
            DiagramSuggestion(
                icon: "arrow.right.arrow.left",
                title: "Trace \(entryPoint)",
                description: "See the execution flow when this method runs.",
                action: .sequenceDiagram(entryPoint: entryPoint),
                requiresPro: true
            )
        }
    }

    private static func dependencySuggestions(from summary: ProjectSummary) -> [DiagramSuggestion] {
        var suggestions: [DiagramSuggestion] = []
        if summary.totalRelationships > 0 {
            suggestions.append(DiagramSuggestion(
                icon: "arrow.triangle.branch",
                title: "See which types depend on each other",
                description: "\(summary.totalRelationships) dependency edges found.",
                action: .dependencyGraph(mode: .types),
                requiresPro: true
            ))
        }
        if summary.moduleImports.count >= 2 {
            suggestions.append(DiagramSuggestion(
                icon: "shippingbox.and.arrow.backward",
                title: "See module dependencies",
                description: "\(summary.moduleImports.count) external modules detected.",
                action: .dependencyGraph(mode: .modules),
                requiresPro: true
            ))
        }
        return suggestions
    }

    private static func stateMachineSuggestions(from summary: ProjectSummary) -> [DiagramSuggestion] {
        summary.stateMachines
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map { model in
                DiagramSuggestion(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Diagram \(model.identifier)",
                    description: stateMachineDescription(for: model),
                    action: .stateMachine(identifier: model.identifier),
                    requiresPro: true
                )
            }
    }

    private static func stateMachineDescription(for model: StateMachineModel) -> String {
        switch model.confidence {
        case .high:
            return "\(model.states.count) states, \(model.transitions.count) transitions."
        case .medium:
            return "\(model.states.count) states — type inferred from initializer."
        case .low:
            return "\(model.transitions.count) transitions — sources unknown."
        }
    }
}
