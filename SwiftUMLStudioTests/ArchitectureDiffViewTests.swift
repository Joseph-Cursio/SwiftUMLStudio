import Foundation
import SwiftUI
@testable import SwiftUMLStudio
import Testing
import ViewInspector

// MARK: - Fixtures

private func makeDiff(
    previousTimestamp: Date = Date().addingTimeInterval(-3_600),
    typeDelta: Int = 0,
    relationshipDelta: Int = 0,
    moduleDelta: Int = 0,
    fileDelta: Int = 0,
    typeBreakdownDeltas: [String: Int] = [:],
    complexityChanges: [(name: String, delta: Int)] = []
) -> ArchitectureDiff {
    ArchitectureDiff(
        previousTimestamp: previousTimestamp,
        typeDelta: typeDelta,
        relationshipDelta: relationshipDelta,
        moduleDelta: moduleDelta,
        fileDelta: fileDelta,
        typeBreakdownDeltas: typeBreakdownDeltas,
        complexityChanges: complexityChanges
    )
}

// MARK: - DeltaLabel

@Suite("DeltaLabel")
@MainActor
struct DeltaLabelTests {

    @Test("positive delta renders with a leading +")
    func positiveDelta() throws {
        let view = DeltaLabel(delta: 5)
        let text = try view.inspect().text().string()
        #expect(text == "+5")
    }

    @Test("negative delta renders with a leading −")
    func negativeDelta() throws {
        let view = DeltaLabel(delta: -3)
        let text = try view.inspect().text().string()
        #expect(text == "-3")
    }

    @Test("zero delta renders as \"0\"")
    func zeroDelta() throws {
        let view = DeltaLabel(delta: 0)
        let text = try view.inspect().text().string()
        #expect(text == "0")
    }
}

// MARK: - DeltaChip

@Suite("DeltaChip")
@MainActor
struct DeltaChipTests {

    @Test("renders the label and embedded DeltaLabel")
    func rendersLabel() throws {
        let view = DeltaChip(label: "Types", delta: 4)
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("Types"))
        #expect(strings.contains("+4"))
    }
}

// MARK: - ArchitectureDiffView

@Suite("ArchitectureDiffView")
@MainActor
struct ArchitectureDiffViewTests {

    @Test("summary row includes four delta chips")
    func summaryFourChips() throws {
        let view = ArchitectureDiffView(diff: makeDiff(
            typeDelta: 2, relationshipDelta: -1, moduleDelta: 0, fileDelta: 3
        ))
        let chips = try view.inspect().findAll(DeltaChip.self)
        #expect(chips.count == 4)
    }

    @Test("breakdown section is hidden when typeBreakdownDeltas is empty")
    func breakdownSectionHidden() throws {
        let view = ArchitectureDiffView(diff: makeDiff())
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("Type Breakdown Changes") == false)
    }

    @Test("breakdown section appears with rows sorted by absolute delta")
    func breakdownSortedByAbsoluteDelta() throws {
        let view = ArchitectureDiffView(diff: makeDiff(
            typeBreakdownDeltas: ["Structs": 1, "Classes": -5, "Enums": 2]
        ))
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("Type Breakdown Changes"))
        // Rows appear in |Δ| order: Classes(-5), Enums(+2), Structs(+1)
        let indexClasses = strings.firstIndex(of: "Classes") ?? Int.max
        let indexEnums = strings.firstIndex(of: "Enums") ?? Int.max
        let indexStructs = strings.firstIndex(of: "Structs") ?? Int.max
        #expect(indexClasses < indexEnums)
        #expect(indexEnums < indexStructs)
    }

    @Test("complexity section is hidden when complexityChanges is empty")
    func complexitySectionHidden() throws {
        let view = ArchitectureDiffView(diff: makeDiff())
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("Complexity Changes") == false)
    }

    @Test("complexity section caps at the top five changes")
    func complexityCapsAtFive() throws {
        let changes: [(name: String, delta: Int)] = [
            ("Alpha", 7), ("Bravo", 6), ("Charlie", 5),
            ("Delta", 4), ("Echo", 3), ("Foxtrot", 2), ("Golf", 1),
        ]
        let view = ArchitectureDiffView(diff: makeDiff(complexityChanges: changes))
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        // First five are present
        for change in changes.prefix(5) {
            #expect(strings.contains(change.name))
        }
        // Sixth is NOT
        #expect(strings.contains("Foxtrot") == false)
    }

    @Test("positive complexity delta uses \"more connections\" label")
    func moreConnectionsLabel() throws {
        let view = ArchitectureDiffView(diff: makeDiff(
            complexityChanges: [(name: "Service", delta: 3)]
        ))
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("more connections"))
        #expect(strings.contains("fewer connections") == false)
    }

    @Test("negative complexity delta uses \"fewer connections\" label")
    func fewerConnectionsLabel() throws {
        let view = ArchitectureDiffView(diff: makeDiff(
            complexityChanges: [(name: "Service", delta: -3)]
        ))
        let strings = try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(strings.contains("fewer connections"))
        #expect(strings.contains("more connections") == false)
    }
}
