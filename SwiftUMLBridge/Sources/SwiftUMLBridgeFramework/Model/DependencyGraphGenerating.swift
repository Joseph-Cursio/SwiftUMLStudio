import Foundation

// MARK: - Dependency Graph Generator Protocol

/// Abstraction for dependency graph generation, enabling mock injection in tests.
public protocol DependencyGraphGenerating: Sendable {
    func generateScript(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration
    ) -> DepsScript

    /// Module-aware entry. Default implementation falls back to the path-based
    /// `generateScript(for:mode:with:)` over all source files in the package
    /// — concrete generators (notably `DependencyGraphGenerator`) override to
    /// also tag each type with the SPM target that declares it.
    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        mode: DepsMode,
        with configuration: Configuration,
        sdkPath: String?
    ) -> DepsScript

    /// The edge list behind a dependency diagram, without the diagram. Same reason as
    /// `ClassDiagramGenerating.analyzeTypes(for:sdkPath:)`: `ProjectAnalyzer` detects cycles
    /// and counts modules off these edges and renders nothing.
    func extractEdges(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration
    ) -> [DependencyEdge]
}

public extension DependencyGraphGenerating {
    /// The dependency edges of the Swift files at `paths` under the default configuration.
    func extractEdges(for paths: [String], mode: DepsMode) -> [DependencyEdge] {
        extractEdges(for: paths, mode: mode, with: .default)
    }

    /// The dependency graph of every source file in the package's targets, in path order, with
    /// no target recorded on its types; `sdkPath` is not used.
    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        mode: DepsMode,
        with configuration: Configuration,
        sdkPath _: String? = nil
    ) -> DepsScript {
        let paths = description.sourceFileToModuleMap(packageRoot: packageRoot).keys.sorted()
        return generateScript(for: paths, mode: mode, with: configuration)
    }
}
