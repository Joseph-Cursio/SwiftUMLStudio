import Foundation

// MARK: - Class Diagram Generator Protocol

/// Abstraction for class diagram generation, enabling mock injection in tests.
public protocol ClassDiagramGenerating: Sendable {
    func generateScript(
        for paths: [String],
        with configuration: Configuration,
        sdkPath: String?
    ) -> DiagramScript

    /// Module-aware entry. Default implementation falls back to the path-based
    /// `generateScript(for:with:sdkPath:)` over all source files in the package
    /// — concrete generators (notably `ClassDiagramGenerator`) override to also
    /// stamp `LayoutNode.module` with each type's owning target.
    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        with configuration: Configuration,
        sdkPath: String?
    ) -> DiagramScript

    /// The type inventory behind a class diagram, without the diagram.
    ///
    /// `ProjectAnalyzer` counts types per module and never renders anything. It was reaching
    /// for `ClassDiagramGenerator` concretely because this was the one thing the protocol did
    /// not offer — the abstraction covered rendering and stopped short of the analysis the
    /// rendering is built on.
    func analyzeTypes(for paths: [String], sdkPath: String?) -> [TypeInfo]
}

/// Default parameter for sdkPath so callers don't need to pass it.
public extension ClassDiagramGenerating {
    /// The class diagram of the Swift files at `paths`, without an SDK path for SourceKit.
    func generateScript(
        for paths: [String],
        with configuration: Configuration
    ) -> DiagramScript {
        generateScript(for: paths, with: configuration, sdkPath: nil)
    }

    /// The types declared in the Swift files at `paths`, without an SDK path for SourceKit.
    func analyzeTypes(for paths: [String]) -> [TypeInfo] {
        analyzeTypes(for: paths, sdkPath: nil)
    }

    /// The class diagram of every source file in the package's targets, in path order, with no
    /// module recorded on its types.
    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        with configuration: Configuration,
        sdkPath: String? = nil
    ) -> DiagramScript {
        let paths = description.sourceFileToModuleMap(packageRoot: packageRoot).keys.sorted()
        return generateScript(for: paths, with: configuration, sdkPath: sdkPath)
    }
}
