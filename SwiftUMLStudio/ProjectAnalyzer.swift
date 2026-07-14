import Foundation
import SwiftUMLBridgeFramework

struct ProjectSummary: Sendable {
    var totalFiles: Int
    var totalTypes: Int
    var typeBreakdown: [String: Int]
    var totalRelationships: Int
    var moduleImports: [String]
    var topConnectedTypes: [(name: String, connectionCount: Int)]
    var cycleWarnings: [String]
    var entryPoints: [String]
    var stateMachines: [StateMachineModel]
    /// Per-SPM-target summary, populated only by the `analyze(package:)`
    /// overload. Empty when the user opened a loose folder rather than a
    /// Swift package.
    var moduleBreakdown: [ModuleSummary]

    nonisolated init(
        totalFiles: Int,
        totalTypes: Int,
        typeBreakdown: [String: Int],
        totalRelationships: Int,
        moduleImports: [String],
        topConnectedTypes: [(name: String, connectionCount: Int)],
        cycleWarnings: [String],
        entryPoints: [String],
        stateMachines: [StateMachineModel],
        moduleBreakdown: [ModuleSummary] = []
    ) {
        self.totalFiles = totalFiles
        self.totalTypes = totalTypes
        self.typeBreakdown = typeBreakdown
        self.totalRelationships = totalRelationships
        self.moduleImports = moduleImports
        self.topConnectedTypes = topConnectedTypes
        self.cycleWarnings = cycleWarnings
        self.entryPoints = entryPoints
        self.stateMachines = stateMachines
        self.moduleBreakdown = moduleBreakdown
    }
}

/// Per-SPM-target stats surfaced by the dashboard when a Swift Package
/// is loaded. Mirrors what `component --package` shows graphically:
/// each target's kind, file count, type count, and outgoing
/// target_dependencies count.
struct ModuleSummary: Sendable, Hashable {
    let name: String
    let kind: SPMTargetDescription.Kind
    let fileCount: Int
    let typeCount: Int
    let outgoingTargetDependencies: Int
}

nonisolated enum ProjectAnalyzer {
    static func analyze(paths: [String]) -> ProjectSummary {
        guard paths.isEmpty == false else {
            return ProjectSummary(
                totalFiles: 0, totalTypes: 0, typeBreakdown: [:],
                totalRelationships: 0, moduleImports: [],
                topConnectedTypes: [], cycleWarnings: [], entryPoints: [],
                stateMachines: []
            )
        }
        let generator = ClassDiagramGenerator()
        let types = generator.analyzeTypes(for: paths)

        let depGenerator = DependencyGraphGenerator()
        let typeEdges = depGenerator.extractEdges(for: paths, mode: .types)
        let moduleEdges = depGenerator.extractEdges(for: paths, mode: .modules)

        let cycles = DependencyGraphModel(edges: typeEdges).detectCycles()

        let entryPoints = SequenceDiagramGenerator().findEntryPoints(for: paths)
        let stateMachines = StateMachineGenerator().findCandidates(for: paths)

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
            entryPoints: entryPoints,
            stateMachines: stateMachines
        )
    }

    /// Module-aware analysis. Reuses `analyze(paths:)` for the cross-package
    /// aggregate fields and enriches the result with a per-target breakdown
    /// (test targets excluded, matching `sourceFileToModuleMap`).
    static func analyze(
        package description: SPMPackageDescription,
        packageRoot: URL
    ) -> ProjectSummary {
        let pathToModule = description.sourceFileToModuleMap(packageRoot: packageRoot)
        let aggregate = analyze(paths: pathToModule.keys.sorted())

        var filesPerModule: [String: Int] = [:]
        for module in pathToModule.values {
            filesPerModule[module, default: 0] += 1
        }

        let typesGenerator = ClassDiagramGenerator()
        var typesPerModule: [String: Int] = [:]
        for target in description.targets where target.kind != .test {
            let targetRoot = packageRoot.appendingPathComponent(target.path)
            let sourcePaths = target.sources.map { targetRoot.appendingPathComponent($0).path }
            typesPerModule[target.name] = typesGenerator.analyzeTypes(for: sourcePaths).count
        }

        let breakdown = description.targets
            .filter { $0.kind != .test }
            .map { target in
                ModuleSummary(
                    name: target.name,
                    kind: target.kind,
                    fileCount: filesPerModule[target.name] ?? 0,
                    typeCount: typesPerModule[target.name] ?? 0,
                    outgoingTargetDependencies: target.dependencies.count
                )
            }
            .sorted { $0.name < $1.name }

        // Mutate a copy; never rebuild field-by-field. This return only adds `moduleBreakdown`
        // to the aggregate — but listing the other nine by hand meant a tenth field added to
        // `ProjectSummary` would be silently dropped here, taking its default instead of failing
        // to compile (`moduleBreakdown` already has a `= []` default, so the initialiser will not
        // complain about a missing argument).
        var summary = aggregate
        summary.moduleBreakdown = breakdown
        return summary
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
