import Foundation
import SwiftUMLBridgeFramework

struct ProjectSummary {
    let totalFiles: Int
    let totalTypes: Int
    let typeBreakdown: [String: Int]
    let totalRelationships: Int
    let moduleImports: [String]
    let topConnectedTypes: [(name: String, connectionCount: Int)]
    let cycleWarnings: [String]
    let entryPoints: [String]
}

enum ProjectAnalyzer {
    static func analyze(paths: [String]) -> ProjectSummary {
        let generator = ClassDiagramGenerator()
        let types = generator.analyzeTypes(for: paths)

        let depGenerator = DependencyGraphGenerator()
        let typeEdges = depGenerator.extractEdges(for: paths, mode: .types)
        let moduleEdges = depGenerator.extractEdges(for: paths, mode: .modules)

        let cycles = DependencyGraphModel(edges: typeEdges).detectCycles()

        let entryPoints = SequenceDiagramGenerator().findEntryPoints(for: paths)

        let typeBreakdown = buildTypeBreakdown(from: types)
        let topConnected = findTopConnectedTypes(from: typeEdges)
        let modules = Array(Set(moduleEdges.map(\.to))).sorted()

        let fileCount = countSwiftFiles(in: paths)

        return ProjectSummary(
            totalFiles: fileCount,
            totalTypes: types.count,
            typeBreakdown: typeBreakdown,
            totalRelationships: typeEdges.count,
            moduleImports: modules,
            topConnectedTypes: topConnected,
            cycleWarnings: cycles.sorted(),
            entryPoints: entryPoints
        )
    }

    // MARK: - Private

    private static func buildTypeBreakdown(from types: [TypeInfo]) -> [String: Int] {
        var breakdown: [String: Int] = [:]
        for typeInfo in types {
            let label = typeInfo.kind.capitalized + "s"
            breakdown[label, default: 0] += 1
        }
        return breakdown
    }

    private static func findTopConnectedTypes(
        from edges: [DependencyEdge]
    ) -> [(name: String, connectionCount: Int)] {
        var counts: [String: Int] = [:]
        for edge in edges {
            counts[edge.to, default: 0] += 1
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, connectionCount: $0.value) }
    }

    private static func countSwiftFiles(in paths: [String]) -> Int {
        var count = 0
        let fileManager = FileManager.default
        for path in paths {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let enumerator = fileManager.enumerator(atPath: path) {
                    while let file = enumerator.nextObject() as? String {
                        if file.hasSuffix(".swift") { count += 1 }
                    }
                }
            } else if path.hasSuffix(".swift") {
                count += 1
            }
        }
        return count
    }
}
