import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - Fixtures

private func makeSummary(
    totalFiles: Int = 5,
    totalTypes: Int = 10,
    typeBreakdown: [String: Int] = ["Classes": 4, "Structs": 3, "Enums": 3],
    totalRelationships: Int = 7,
    moduleImports: [String] = [],
    entryPoints: [String] = ["Foo.bar", "Baz.qux"],
    stateMachines: [StateMachineModel] = []
) -> ProjectSummary {
    ProjectSummary(
        totalFiles: totalFiles,
        totalTypes: totalTypes,
        typeBreakdown: typeBreakdown,
        totalRelationships: totalRelationships,
        moduleImports: moduleImports,
        topConnectedTypes: [],
        cycleWarnings: [],
        entryPoints: entryPoints,
        stateMachines: stateMachines
    )
}

private func makeInsight(
    title: String = "Example",
    description: String = "Example insight",
    severity: Insight.Severity = .info
) -> Insight {
    Insight(icon: "info.circle", title: title, description: description, severity: severity)
}

private func makeSuggestion(
    title: String = "Example",
    description: String = "Example suggestion",
    requiresPro: Bool = false,
    action: SuggestionAction = .classDiagram
) -> DiagramSuggestion {
    DiagramSuggestion(
        icon: "doc", title: title, description: description,
        action: action, requiresPro: requiresPro
    )
}

// MARK: - StatCardView

@Suite("StatCardView")
@MainActor
struct StatCardViewTests {

    @Test("renders value, label, and system image")
    func rendersAll() throws {
        let view = StatCardView(value: 42, label: "Files", icon: "doc.text")
        let stack = try view.inspect().vStack()

        let texts = stack.findAll(ViewType.Text.self)
        let strings = try texts.map { try $0.string() }
        #expect(strings.contains("42"))
        #expect(strings.contains("Files"))

        let image = try stack.image(0)
        #expect(try image.actualImage().name() == "doc.text")
    }

    @Test("zero value renders as \"0\"")
    func zeroValue() throws {
        let view = StatCardView(value: 0, label: "Methods", icon: "function")
        let stack = try view.inspect().vStack()
        let strings = try stack.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("0"))
    }
}

// MARK: - TypeBreakdownGrid

@Suite("TypeBreakdownGrid")
@MainActor
struct TypeBreakdownGridTests {

    @Test("renders Type Breakdown header")
    func rendersHeader() throws {
        let view = TypeBreakdownGrid(summary: makeSummary())
        let titles = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(titles.contains("Type Breakdown"))
    }

    @Test("renders one row per type-breakdown entry")
    func rendersBreakdownEntries() throws {
        let breakdown = ["Classes": 4, "Structs": 3, "Enums": 2]
        let view = TypeBreakdownGrid(summary: makeSummary(typeBreakdown: breakdown))
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        for (kind, count) in breakdown {
            #expect(strings.contains(kind))
            #expect(strings.contains("\(count)"))
        }
    }

    @Test("entries are sorted by count descending")
    func sortedByCount() throws {
        let breakdown = ["A": 2, "B": 9, "C": 5]
        let view = TypeBreakdownGrid(summary: makeSummary(typeBreakdown: breakdown))
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        // The kind labels should appear in the order B, C, A
        let indexB = strings.firstIndex(of: "B") ?? Int.max
        let indexC = strings.firstIndex(of: "C") ?? Int.max
        let indexA = strings.firstIndex(of: "A") ?? Int.max
        #expect(indexB < indexC)
        #expect(indexC < indexA)
    }
}

// MARK: - InsightRowView

@Suite("InsightRowView")
@MainActor
struct InsightRowViewRenderingTests {

    @Test("renders title and description")
    func rendersInsightText() throws {
        let insight = makeInsight(title: "Cycles detected", description: "Two types in a cycle")
        let view = InsightRowView(insight: insight)
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("Cycles detected"))
        #expect(strings.contains("Two types in a cycle"))
    }

    @Test("uses the insight's icon")
    func rendersIcon() throws {
        let insight = makeInsight()
        let view = InsightRowView(insight: insight)
        let image = try view.inspect().hStack().image(0)
        #expect(try image.actualImage().name() == "info.circle")
    }
}

// MARK: - SuggestionCardView

@Suite("SuggestionCardView")
@MainActor
struct SuggestionCardViewTests {

    @Test("renders title, description, and leading icon")
    func rendersContent() throws {
        let suggestion = makeSuggestion(title: "Class Diagram", description: "See your types")
        let view = SuggestionCardView(suggestion: suggestion, onTap: { _ in })
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("Class Diagram"))
        #expect(strings.contains("See your types"))

        let images = try view.inspect().findAll(ViewType.Image.self)
        let imageNames = images.compactMap { try? $0.actualImage().name() }
        #expect(imageNames.contains("doc"))
        #expect(imageNames.contains("chevron.right"))
    }

    @Test("shows lock icon when Pro is required")
    func proLockVisible() throws {
        let suggestion = makeSuggestion(requiresPro: true)
        let view = SuggestionCardView(suggestion: suggestion, onTap: { _ in })
        let images = try view.inspect().findAll(ViewType.Image.self)
        let names = images.compactMap { try? $0.actualImage().name() }
        #expect(names.contains("lock.fill"))
    }

    @Test("omits lock icon when free")
    func proLockHidden() throws {
        let suggestion = makeSuggestion(requiresPro: false)
        let view = SuggestionCardView(suggestion: suggestion, onTap: { _ in })
        let images = try view.inspect().findAll(ViewType.Image.self)
        let names = images.compactMap { try? $0.actualImage().name() }
        #expect(names.contains("lock.fill") == false)
    }

    @Test("tapping the button fires the onTap closure with the suggestion")
    func tapFiresClosure() throws {
        let suggestion = makeSuggestion(title: "Tapped")
        var captured: DiagramSuggestion?
        let view = SuggestionCardView(suggestion: suggestion, onTap: { captured = $0 })
        try view.inspect().find(ViewType.Button.self).tap()
        #expect(captured?.title == "Tapped")
    }
}

// MARK: - ProjectDashboardView

@Suite("ProjectDashboardView")
@MainActor
struct ProjectDashboardViewTests {

    @Test("nil summary shows the empty-state placeholder, not the content scroll view")
    func nilSummaryShowsEmpty() throws {
        let view = ProjectDashboardView(
            summary: nil, insights: [], suggestions: [],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        // Empty state is rendered; populated-state scroll view is not.
        #expect(throws: InspectionError.self) {
            try view.inspect().find(viewWithAccessibilityIdentifier: "dashboardContent")
        }
        // Five stat cards only render in populated state.
        #expect(try view.inspect().findAll(StatCardView.self).isEmpty)
    }

    @Test("populated summary shows dashboard content")
    func populatedShowsContent() throws {
        let view = ProjectDashboardView(
            summary: makeSummary(), insights: [], suggestions: [],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        _ = try view.inspect().find(viewWithAccessibilityIdentifier: "dashboardContent")
    }

    @Test("stats bar contains five stat cards")
    func statsBarFiveCards() throws {
        let view = ProjectDashboardView(
            summary: makeSummary(), insights: [], suggestions: [],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        let cards = try view.inspect().findAll(StatCardView.self)
        #expect(cards.count == 5)
    }

    @Test("insights section hidden when insights array is empty")
    func insightsSectionHiddenWhenEmpty() throws {
        let view = ProjectDashboardView(
            summary: makeSummary(), insights: [], suggestions: [],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        let insightsText = try view.inspect().findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(insightsText.contains("Insights") == false)
    }

    @Test("insights section visible when insights present")
    func insightsSectionVisibleWhenPresent() throws {
        let view = ProjectDashboardView(
            summary: makeSummary(),
            insights: [makeInsight()],
            suggestions: [],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        let strings = try view.inspect().findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("Insights"))
    }

    @Test("suggestions section visible when suggestions present")
    func suggestionsSectionVisibleWhenPresent() throws {
        let view = ProjectDashboardView(
            summary: makeSummary(),
            insights: [],
            suggestions: [makeSuggestion()],
            architectureDiff: nil, isProUnlocked: false,
            onSuggestionTap: { _ in }
        )
        let strings = try view.inspect().findAll(ViewType.Text.self)
            .compactMap { try? $0.string() }
        #expect(strings.contains("Suggested Diagrams"))
    }
}
