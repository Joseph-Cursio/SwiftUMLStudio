import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

// MARK: - GCD dispatch helpers

private func runOnMain(_ block: @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync { MainActor.assumeIsolated(block) }
    }
}

private func makeSummary(
    totalFiles: Int = 3,
    totalTypes: Int = 5,
    typeBreakdown: [String: Int] = ["Classes": 5],
    totalRelationships: Int = 2,
    moduleImports: [String] = [],
    topConnectedTypes: [(name: String, connectionCount: Int)] = [],
    cycleWarnings: [String] = [],
    entryPoints: [String] = [],
    stateMachines: [StateMachineModel] = [],
    moduleBreakdown: [ModuleSummary] = []
) -> ProjectSummary {
    ProjectSummary(
        totalFiles: totalFiles,
        totalTypes: totalTypes,
        typeBreakdown: typeBreakdown,
        totalRelationships: totalRelationships,
        moduleImports: moduleImports,
        topConnectedTypes: topConnectedTypes,
        cycleWarnings: cycleWarnings,
        entryPoints: entryPoints,
        stateMachines: stateMachines,
        moduleBreakdown: moduleBreakdown
    )
}

private func makeModule(_ name: String, kind: SPMTargetDescription.Kind = .library) -> ModuleSummary {
    ModuleSummary(
        name: name, kind: kind,
        fileCount: 4, typeCount: 6, outgoingTargetDependencies: 1
    )
}

// MARK: - InsightEngine Tests

struct InsightEngineTests {

    @Test("generates cycle warning when cycles present")
    func cycleWarning() throws {
        runOnMain {
            let summary = makeSummary(cycleWarnings: ["TypeA", "TypeB"])
            let insights = InsightEngine.generate(from: summary)
            let cycleInsight = insights.first { $0.title.contains("Circular") }
            #expect(cycleInsight != nil, "Expected a cycle warning insight")
            #expect(cycleInsight?.severity == .warning)
        }
    }

    @Test("generates composition insight when types exist")
    func compositionInsight() {
        runOnMain {
            let summary = makeSummary(totalTypes: 7, typeBreakdown: ["Classes": 4, "Structs": 3])
            let insights = InsightEngine.generate(from: summary)
            let comp = insights.first { $0.title.contains("composition") }
            #expect(comp != nil, "Expected a composition insight")
        }
    }

    @Test("generates high-connectivity insight for popular types")
    func highConnectivity() {
        runOnMain {
            let summary = makeSummary(
                topConnectedTypes: [(name: "Database", connectionCount: 12)]
            )
            let insights = InsightEngine.generate(from: summary)
            let conn = insights.first { $0.title.contains("Database") }
            #expect(conn != nil, "Expected a connectivity insight for Database")
            #expect(conn?.severity == .noteworthy)
        }
    }

    @Test("generates entry points insight when methods available")
    func entryPointInsight() {
        runOnMain {
            let summary = makeSummary(entryPoints: ["Foo.bar", "Baz.qux"])
            let insights = InsightEngine.generate(from: summary)
            let method = insights.first { $0.title.contains("methods") }
            #expect(method != nil, "Expected an entry points insight")
        }
    }

    @Test("generates state machine insight when candidates detected")
    func stateMachineInsight() {
        runOnMain {
            let model = StateMachineModel(
                hostType: "TrafficLight", enumType: "Light",
                states: [StateMachineState(name: "red", isInitial: true)],
                transitions: []
            )
            let summary = makeSummary(stateMachines: [model])
            let insights = InsightEngine.generate(from: summary)
            let stateInsight = insights.first { $0.title.contains("state machine") }
            #expect(stateInsight != nil, "Expected a state machine insight")
            #expect(stateInsight?.description.contains("TrafficLight") == true)
        }
    }
}

// MARK: - SuggestionEngine Tests

struct SuggestionEngineTests {

    @Test("always suggests class diagram when types exist")
    func classDiagramSuggestion() {
        runOnMain {
            let summary = makeSummary()
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: false)
            let classSug = suggestions.first { $0.requiresPro == false }
            #expect(classSug != nil, "Expected a free class diagram suggestion")
        }
    }

    @Test("suggests sequence diagrams for entry points as Pro")
    func sequenceSuggestionIsPro() {
        runOnMain {
            let summary = makeSummary(entryPoints: ["Foo.bar"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: false)
            let seqSug = suggestions.first { $0.title.contains("Trace") }
            #expect(seqSug != nil, "Expected a sequence diagram suggestion")
            #expect(seqSug?.requiresPro == true)
        }
    }

    @Test("suggests dependency graph when relationships exist")
    func dependencyGraphSuggestion() {
        runOnMain {
            let summary = makeSummary(totalRelationships: 8)
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let deps = suggestions.first { $0.title.contains("depend") }
            #expect(deps != nil, "Expected a dependency graph suggestion")
        }
    }

    @Test("no suggestions when no types")
    func emptyProject() {
        runOnMain {
            let summary = makeSummary(totalFiles: 0, totalTypes: 0, typeBreakdown: [:], totalRelationships: 0)
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            #expect(suggestions.isEmpty)
        }
    }

    // MARK: - ER

    @Test(
        "suggests an ER diagram for each supported persistence stack",
        arguments: ["SwiftData", "CoreData", "GRDB", "SQLite"]
    )
    func erSuggestionPerStack(framework: String) {
        runOnMain {
            let summary = makeSummary(moduleImports: [framework])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let entry = suggestions.first { $0.title.contains("data is stored") }

            #expect(entry != nil, "expected an ER suggestion for \(framework)")
            #expect(entry?.requiresPro == true)
            #expect(
                entry?.description.contains(framework) == true,
                "the card should name the stack it detected"
            )
        }
    }

    /// Without a persistence import an ER diagram would render nothing, so
    /// offering the card would send the user to an empty canvas.
    @Test("no ER suggestion when the project imports no persistence stack")
    func noERSuggestionWithoutPersistence() {
        runOnMain {
            let summary = makeSummary(moduleImports: ["Foundation", "Combine", "SwiftUI"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)

            #expect(suggestions.contains { $0.title.contains("data is stored") } == false)
        }
    }

    @Test("only one ER suggestion when a project mixes two stacks")
    func singleERSuggestionForMixedStacks() {
        runOnMain {
            let summary = makeSummary(moduleImports: ["SwiftData", "GRDB"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)

            #expect(suggestions.filter { $0.title.contains("data is stored") }.count == 1)
        }
    }

    // MARK: - Component

    @Test("suggests a component diagram when a multi-target package is loaded")
    func componentSuggestion() {
        runOnMain {
            let summary = makeSummary(
                moduleBreakdown: [makeModule("App", kind: .executable), makeModule("Core")]
            )
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let entry = suggestions.first { $0.title.contains("package fits together") }

            #expect(entry != nil)
            #expect(entry?.requiresPro == true)
            #expect(entry?.description.contains("2 build targets") == true)
        }
    }

    /// `moduleBreakdown` is empty for a loose folder, and a one-target package
    /// draws a single box with no edges — neither is worth a card.
    @Test(
        "no component suggestion for a loose folder or a single-target package",
        arguments: [0, 1]
    )
    func noComponentSuggestionBelowTwoTargets(targetCount: Int) {
        runOnMain {
            let modules = (0..<targetCount).map { makeModule("Target\($0)") }
            let summary = makeSummary(moduleBreakdown: modules)
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)

            #expect(suggestions.contains { $0.title.contains("package fits together") } == false)
        }
    }

    // MARK: - Activity

    @Test("suggests an activity diagram for the top entry point")
    func activitySuggestion() {
        runOnMain {
            let summary = makeSummary(entryPoints: ["Foo.bar"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let entry = suggestions.first { $0.title.contains("Step through") }

            #expect(entry != nil)
            #expect(entry?.requiresPro == true)
            #expect(entry?.title.contains("Foo.bar") == true)
        }
    }

    /// Sequence offers three cards; activity offers one. Both are driven by the
    /// same `entryPoints`, so matching sequence's count would double the card
    /// load on the same handful of methods.
    @Test("activity offers one card even when many entry points exist")
    func activityIsCappedAtOne() {
        runOnMain {
            let summary = makeSummary(entryPoints: ["A.one", "B.two", "C.three", "D.four"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)

            #expect(suggestions.filter { $0.title.contains("Step through") }.count == 1)
            #expect(suggestions.filter { $0.title.contains("Trace") }.count == 3)
        }
    }

    /// The two cards must not read as duplicates: sequence answers "which types
    /// does this call", activity answers "what happens inside it".
    @Test("the activity and sequence cards for one method are distinguishable")
    func activityAndSequenceReadDifferently() {
        runOnMain {
            let summary = makeSummary(entryPoints: ["Foo.bar"])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let activity = suggestions.first { $0.title.contains("Step through") }
            let sequence = suggestions.first { $0.title.contains("Trace") }

            #expect(activity?.title != sequence?.title)
            #expect(activity?.description != sequence?.description)
            #expect(activity?.icon != sequence?.icon)
        }
    }

    @Test("no activity suggestion without entry points")
    func noActivitySuggestionWithoutEntryPoints() {
        runOnMain {
            let summary = makeSummary(entryPoints: [])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)

            #expect(suggestions.contains { $0.title.contains("Step through") } == false)
        }
    }

    // MARK: - Reachability

    /// Explorer navigation is entirely suggestion-driven, so a diagram type with
    /// no card is unreachable in that mode. All seven modes are now covered.
    @Test("every diagram mode is reachable from some suggestion")
    func everyModeIsReachable() {
        runOnMain {
            let summary = makeSummary(
                totalRelationships: 4,
                moduleImports: ["SwiftData", "Alamofire"],
                entryPoints: ["Foo.bar"],
                stateMachines: [
                    StateMachineModel(
                        hostType: "Light", enumType: "Phase",
                        states: [], transitions: [],
                        confidence: .high, notes: []
                    )
                ],
                moduleBreakdown: [makeModule("App", kind: .executable), makeModule("Core")]
            )
            let actions = SuggestionEngine.generate(from: summary, isProUnlocked: true).map(\.action)

            #expect(actions.contains { if case .classDiagram = $0 { true } else { false } })
            #expect(actions.contains { if case .sequenceDiagram = $0 { true } else { false } })
            #expect(actions.contains { if case .dependencyGraph = $0 { true } else { false } })
            #expect(actions.contains { if case .stateMachine = $0 { true } else { false } })
            #expect(actions.contains { if case .activityDiagram = $0 { true } else { false } })
            #expect(actions.contains { if case .erDiagram = $0 { true } else { false } })
            #expect(actions.contains { if case .componentDiagram = $0 { true } else { false } })
        }
    }

    @Test("suggests state machine diagrams as Pro for each detected candidate")
    func stateMachineSuggestionIsPro() {
        runOnMain {
            let model = StateMachineModel(
                hostType: "Loader", enumType: "State",
                states: [StateMachineState(name: "idle", isInitial: true)],
                transitions: [StateTransition(from: "idle", toState: "busy", trigger: "start")]
            )
            let summary = makeSummary(stateMachines: [model])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: false)
            let stateSug = suggestions.first { $0.title.contains("Loader.State") }
            #expect(stateSug != nil, "Expected a state machine suggestion")
            #expect(stateSug?.requiresPro == true)
            switch stateSug?.action {
            case .stateMachine(let identifier): #expect(identifier == "Loader.State")
            default: Issue.record("Expected a stateMachine action")
            }
        }
    }

    @Test("state machine suggestions are ordered by confidence (high first)")
    func stateMachineSuggestionsOrderedByConfidence() {
        runOnMain {
            let low = StateMachineModel(
                hostType: "Lo", enumType: "L",
                states: [], transitions: [], confidence: .low, notes: []
            )
            let high = StateMachineModel(
                hostType: "Hi", enumType: "H",
                states: [], transitions: [], confidence: .high, notes: []
            )
            let medium = StateMachineModel(
                hostType: "Me", enumType: "M",
                states: [], transitions: [], confidence: .medium, notes: []
            )
            let summary = makeSummary(stateMachines: [low, high, medium])
            let suggestions = SuggestionEngine.generate(from: summary, isProUnlocked: true)
            let stateSuggestions = suggestions.compactMap { suggestion -> String? in
                if case .stateMachine(let identifier) = suggestion.action { return identifier }
                return nil
            }
            #expect(stateSuggestions == ["Hi.H", "Me.M", "Lo.L"])
        }
    }
}
