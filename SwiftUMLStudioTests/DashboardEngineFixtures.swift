import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

func makeSummary(
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
