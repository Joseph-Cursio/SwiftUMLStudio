import Foundation
@testable import SwiftUMLStudio
import Testing

// MARK: - InsightEngine coverage gaps

@MainActor
struct InsightEngineCoverageTests {

    @Test("generates module import insight when 2+ modules present")
    func moduleImportInsight() {
        let summary = ProjectSummary(
            totalFiles: 5, totalTypes: 10,
            typeBreakdown: ["Classes": 10],
            totalRelationships: 3,
            moduleImports: ["Foundation", "SwiftUI", "Combine"],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        let moduleInsight = insights.first { $0.title.contains("modules imported") }
        #expect(moduleInsight != nil, "Expected a module import insight")
    }

    @Test("generates no-relationships insight when types exist but no edges")
    func noRelationshipsInsight() {
        let summary = ProjectSummary(
            totalFiles: 3, totalTypes: 5,
            typeBreakdown: ["Structs": 5],
            totalRelationships: 0,
            moduleImports: [],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        let noRels = insights.first { $0.title.contains("No type relationships") }
        #expect(noRels != nil, "Expected a no-relationships insight")
    }

    @Test("no insights generated for empty project")
    func emptyProjectInsights() {
        let summary = ProjectSummary(
            totalFiles: 0, totalTypes: 0,
            typeBreakdown: [:],
            totalRelationships: 0,
            moduleImports: [],
            topConnectedTypes: [],
            cycleWarnings: [],
            entryPoints: [],
            stateMachines: []
        )
        let insights = InsightEngine.generate(from: summary)
        #expect(insights.isEmpty)
    }
}
