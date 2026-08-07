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
    case activityDiagram(entryPoint: String)
    case erDiagram
    case componentDiagram
}

nonisolated enum SuggestionEngine {
    static func generate(from summary: ProjectSummary, isProUnlocked: Bool) -> [DiagramSuggestion] {
        var suggestions: [DiagramSuggestion] = []
        if let classSuggestion = classDiagramSuggestion(from: summary) {
            suggestions.append(classSuggestion)
        }
        suggestions.append(contentsOf: sequenceSuggestions(from: summary))
        suggestions.append(contentsOf: activitySuggestions(from: summary))
        suggestions.append(contentsOf: dependencySuggestions(from: summary))
        suggestions.append(contentsOf: stateMachineSuggestions(from: summary))
        if let erSuggestion = erDiagramSuggestion(from: summary) {
            suggestions.append(erSuggestion)
        }
        if let componentSuggestion = componentDiagramSuggestion(from: summary) {
            suggestions.append(componentSuggestion)
        }
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

    /// Activity and sequence diagrams answer different questions about the same
    /// method: sequence shows which *types* it calls, activity shows the
    /// branching and looping *inside* it. Both are driven by `entryPoints`, so
    /// offering three of each would double the card count on the same handful of
    /// methods.
    ///
    /// Only the top entry point gets an activity card. That demonstrates the
    /// distinction without crowding out the class, deps, ER and component cards
    /// — the dashboard grid renders every suggestion with no cap of its own.
    private static func activitySuggestions(from summary: ProjectSummary) -> [DiagramSuggestion] {
        summary.entryPoints.prefix(1).map { entryPoint in
            DiagramSuggestion(
                icon: "flowchart",
                title: "Step through \(entryPoint)",
                description: "The branches, loops and error paths inside this method.",
                action: .activityDiagram(entryPoint: entryPoint),
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

    /// Persistence frameworks whose presence means an ER diagram will render
    /// something. Matches the four stacks `ERDiagramGenerator` understands.
    ///
    /// Detected from `moduleImports` rather than by running the ER extractor:
    /// the import list is already computed by the analyzer, so this costs
    /// nothing, whereas an extra extraction pass would parse every file again
    /// just to decide whether to offer a card. The trade is that a project
    /// vendoring one of these stacks without importing it by name goes
    /// undetected — rare in practice, and the mode is still reachable from the
    /// Developer-mode sidebar.
    private static let persistenceModules = ["SwiftData", "CoreData", "GRDB", "SQLite"]

    private static func erDiagramSuggestion(from summary: ProjectSummary) -> DiagramSuggestion? {
        let detected = summary.moduleImports.filter { persistenceModules.contains($0) }
        guard let framework = detected.first else { return nil }
        return DiagramSuggestion(
            icon: "tablecells",
            title: "See how your data is stored",
            description: "This project uses \(framework) — view your models and how they relate.",
            action: .erDiagram,
            requiresPro: true
        )
    }

    private static func componentDiagramSuggestion(from summary: ProjectSummary) -> DiagramSuggestion? {
        // Component diagrams are package-scoped: `moduleBreakdown` is populated
        // only by `analyze(package:)`, so a non-empty breakdown is exactly the
        // condition under which this mode has anything to draw.
        guard summary.moduleBreakdown.count >= 2 else { return nil }
        return DiagramSuggestion(
            icon: "shippingbox",
            title: "See how your package fits together",
            description: "\(summary.moduleBreakdown.count) build targets and what each one offers.",
            action: .componentDiagram,
            requiresPro: true
        )
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
