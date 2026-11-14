import Foundation

// MARK: - Component Diagram Generator Protocol

/// Abstraction for Component diagram generation, enabling mock injection in
/// tests. Component diagrams are inherently package-scoped (one component per
/// SPM target plus their `target_dependencies` edges), so the only entry takes
/// a parsed `SPMPackageDescription` rather than loose source paths.
public protocol ComponentDiagramGenerating: Sendable {
    func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        with configuration: Configuration
    ) -> ComponentScript
}
