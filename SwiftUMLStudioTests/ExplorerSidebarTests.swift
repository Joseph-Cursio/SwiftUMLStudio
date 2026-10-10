import Foundation
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

@Suite("ExplorerSidebar")
@MainActor
struct ExplorerSidebarTests {

    /// `SubscriptionManager` starts unlocked and only re-checks entitlements
    /// after an `await`, so a synchronous inspection always sees Pro unlocked.
    private func inspect(_ viewModel: DiagramViewModel) throws -> InspectableView<ViewType.ClassifiedView> {
        try ExplorerSidebar(viewModel: viewModel, subscriptionManager: SubscriptionManager()).inspect()
    }

    private func makeViewModel() -> DiagramViewModel {
        DiagramViewModel(persistenceController: .init(inMemory: true))
    }

    private func strings(_ viewModel: DiagramViewModel) throws -> [String] {
        try inspect(viewModel).findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("no insights or suggestions shows the open-a-project placeholder")
    func emptyStatePlaceholder() throws {
        let strings = try strings(makeViewModel())
        #expect(strings.contains("Open a project"))
        #expect(strings.contains("Drop a folder to see insights and suggestions."))
        #expect(!strings.contains("Insights"))
        #expect(!strings.contains("Suggested Diagrams"))
    }

    @Test("insights render under an Insights section")
    func rendersInsights() throws {
        let viewModel = makeViewModel()
        viewModel.insights = [
            Insight(icon: "info.circle", title: "Big module", description: "It has 40 types", severity: .noteworthy)
        ]
        let strings = try strings(viewModel)
        #expect(strings.contains("Insights"))
        #expect(strings.contains("Big module"))
        #expect(strings.contains("It has 40 types"))
        #expect(!strings.contains("Open a project"))
        #expect(!strings.contains("Suggested Diagrams"))
    }

    @Test("suggestions render under a Suggested Diagrams section")
    func rendersSuggestions() throws {
        let viewModel = makeViewModel()
        viewModel.suggestions = [
            DiagramSuggestion(
                icon: "doc", title: "Map dependencies", description: "See module edges",
                action: .classDiagram, requiresPro: false
            )
        ]
        let strings = try strings(viewModel)
        #expect(strings.contains("Suggested Diagrams"))
        #expect(strings.contains("Map dependencies"))
        #expect(strings.contains("See module edges"))
        #expect(!strings.contains("Insights"))
    }

    @Test("tapping a suggestion applies it to the view model")
    func tappingSuggestionAppliesIt() throws {
        let viewModel = makeViewModel()
        viewModel.suggestions = [
            DiagramSuggestion(
                icon: "doc", title: "ER", description: "Entities",
                action: .erDiagram, requiresPro: true
            )
        ]
        try inspect(viewModel).find(SuggestionCardView.self).button().tap()
        #expect(viewModel.diagramMode == .erDiagram)
        #expect(viewModel.isGenerating)
    }

    @Test("snapshots render under Architecture Snapshots when Pro is unlocked")
    func rendersSnapshots() throws {
        let viewModel = makeViewModel()
        viewModel.snapshots = [
            ProjectSnapshot(
                identifier: UUID(), timestamp: Date(),
                typeCount: 12, relationshipCount: 7, moduleCount: 4, fileCount: 5
            )
        ]
        let strings = try strings(viewModel)
        #expect(strings.contains("Architecture Snapshots"))
        #expect(strings.contains("12 types"))
    }

    @Test("no snapshots hides the Architecture Snapshots section")
    func hidesEmptySnapshots() throws {
        #expect(!(try strings(makeViewModel())).contains("Architecture Snapshots"))
    }

    @Test("Pro users get the review-reminder toggle")
    func reviewReminderToggle() throws {
        let toggle = try inspect(makeViewModel()).find(ViewType.Toggle.self)
        #expect(try toggle.labelView().text().string() == "Remind me to review")
        #expect(try strings(makeViewModel()).contains("Review Reminders"))
    }

    @Test("History section falls back to the empty-history placeholder")
    func emptyHistory() throws {
        let strings = try strings(makeViewModel())
        #expect(strings.contains("History"))
        #expect(strings.contains("No history yet"))
    }
}
