import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

@Suite("ExplorerSidebar")
@MainActor
struct ExplorerSidebarTests {

    /// `SubscriptionManager` stays unlocked here: the tests run without a
    /// StoreKit configuration, so no products load and Pro stays unlocked.
    private func makeSidebar(_ viewModel: DiagramViewModel) -> ExplorerSidebar {
        ExplorerSidebar(viewModel: viewModel, subscriptionManager: SubscriptionManager())
    }

    private func makeViewModel() -> DiagramViewModel {
        DiagramViewModel(persistenceController: .init(inMemory: true))
    }

    private func strings(_ viewModel: DiagramViewModel) async throws -> [String] {
        try await makeSidebar(viewModel).inspectHosted { view in
            view.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        }
    }

    @Test("no insights or suggestions shows the open-a-project placeholder")
    func emptyStatePlaceholder() async throws {
        let strings = try await strings(makeViewModel())
        #expect(strings.contains("Open a project"))
        #expect(strings.contains("Drop a folder to see insights and suggestions."))
        #expect(!strings.contains("Insights"))
        #expect(!strings.contains("Suggested Diagrams"))
    }

    @Test("insights render under an Insights section")
    func rendersInsights() async throws {
        let viewModel = makeViewModel()
        viewModel.insights = [
            Insight(icon: "info.circle", title: "Big module", description: "It has 40 types", severity: .noteworthy)
        ]
        let strings = try await strings(viewModel)
        #expect(strings.contains("Insights"))
        #expect(strings.contains("Big module"))
        #expect(strings.contains("It has 40 types"))
        #expect(!strings.contains("Open a project"))
        #expect(!strings.contains("Suggested Diagrams"))
    }

    @Test("suggestions render under a Suggested Diagrams section")
    func rendersSuggestions() async throws {
        let viewModel = makeViewModel()
        viewModel.suggestions = [
            DiagramSuggestion(
                icon: "doc", title: "Map dependencies", description: "See module edges",
                action: .classDiagram, requiresPro: false
            )
        ]
        let strings = try await strings(viewModel)
        #expect(strings.contains("Suggested Diagrams"))
        #expect(strings.contains("Map dependencies"))
        #expect(strings.contains("See module edges"))
        #expect(!strings.contains("Insights"))
    }

    @Test("tapping a suggestion applies it to the view model")
    func tappingSuggestionAppliesIt() async throws {
        let viewModel = makeViewModel()
        viewModel.suggestions = [
            DiagramSuggestion(
                icon: "doc", title: "ER", description: "Entities",
                action: .erDiagram, requiresPro: true
            )
        ]
        try await makeSidebar(viewModel).inspectHosted { view in
            try view.find(SuggestionCardView.self).button().tap()
        }
        #expect(viewModel.diagramMode == .erDiagram)
        #expect(viewModel.isGenerating)
    }

    @Test("snapshots render under Architecture Snapshots when Pro is unlocked")
    func rendersSnapshots() async throws {
        let viewModel = makeViewModel()
        viewModel.snapshots = [
            ProjectSnapshot(
                identifier: UUID(), timestamp: Date(),
                typeCount: 12, relationshipCount: 7, moduleCount: 4, fileCount: 5
            )
        ]
        let strings = try await strings(viewModel)
        #expect(strings.contains("Architecture Snapshots"))
        #expect(strings.contains("12 types"))
    }

    @Test("no snapshots hides the Architecture Snapshots section")
    func hidesEmptySnapshots() async throws {
        #expect(!(try await strings(makeViewModel())).contains("Architecture Snapshots"))
    }

    @Test("Pro users get the review-reminder toggle")
    func reviewReminderToggle() async throws {
        let label = try await makeSidebar(makeViewModel()).inspectHosted { view in
            try view.find(ViewType.Toggle.self).labelView().text().string()
        }
        #expect(label == "Remind me to review")
        #expect(try await strings(makeViewModel()).contains("Review Reminders"))
    }

    @Test("History section falls back to the empty-history placeholder")
    func emptyHistory() async throws {
        let strings = try await strings(makeViewModel())
        #expect(strings.contains("History"))
        #expect(strings.contains("No history yet"))
    }
}
