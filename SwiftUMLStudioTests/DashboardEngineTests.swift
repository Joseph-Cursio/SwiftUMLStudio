import Foundation
import Testing
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
    entryPoints: [String] = []
) -> ProjectSummary {
    ProjectSummary(
        totalFiles: totalFiles,
        totalTypes: totalTypes,
        typeBreakdown: typeBreakdown,
        totalRelationships: totalRelationships,
        moduleImports: moduleImports,
        topConnectedTypes: topConnectedTypes,
        cycleWarnings: cycleWarnings,
        entryPoints: entryPoints
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
}
