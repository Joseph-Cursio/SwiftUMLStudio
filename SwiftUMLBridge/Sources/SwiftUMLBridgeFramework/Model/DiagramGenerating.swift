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
}

/// Default parameter for sdkPath so callers don't need to pass it.
public extension ClassDiagramGenerating {
    func generateScript(
        for paths: [String],
        with configuration: Configuration
    ) -> DiagramScript {
        generateScript(for: paths, with: configuration, sdkPath: nil)
    }

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

// MARK: - Sequence Diagram Generator Protocol

/// Abstraction for sequence diagram generation, enabling mock injection in tests.
public protocol SequenceDiagramGenerating: Sendable {
    func findEntryPoints(for paths: [String]) -> [String]

    func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        depth: Int,
        with configuration: Configuration
    ) -> SequenceScript
}

// MARK: - Dependency Graph Generator Protocol

/// Abstraction for dependency graph generation, enabling mock injection in tests.
public protocol DependencyGraphGenerating: Sendable {
    func generateScript(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration
    ) -> DepsScript
}

// MARK: - State Machine Generator Protocol

/// Abstraction for state machine diagram generation, enabling mock injection in tests.
public protocol StateMachineGenerating: Sendable {
    /// Find all candidate state machines (host type + enum type pairs) in the given sources.
    func findCandidates(for paths: [String]) -> [StateMachineModel]

    /// Generate a `StateScript` for a specific candidate identified by `"HostType.EnumType"`.
    func generateScript(
        for paths: [String],
        stateIdentifier: String,
        with configuration: Configuration
    ) -> StateScript
}

// MARK: - Activity Diagram Generator Protocol

/// Abstraction for activity (control-flow) diagram generation, enabling mock injection in tests.
public protocol ActivityDiagramGenerating: Sendable {
    /// Find all potential entry points (`Type.method`) in the given sources.
    func findEntryPoints(for paths: [String]) -> [String]

    /// Generate an activity diagram script for a specific entry function.
    func generateScript(
        for paths: [String],
        entryType: String,
        entryMethod: String,
        with configuration: Configuration
    ) -> ActivityScript
}

// MARK: - ER Diagram Generator Protocol

/// Abstraction for Entity-Relationship diagram generation, enabling mock
/// injection in tests. Unlike behavioral diagrams, an ER diagram covers the
/// whole project in one pass, so there is no entry-point selector.
public protocol ERDiagramGenerating: Sendable {
    /// Generate an ER diagram script for the persisted types in the given sources.
    func generateScript(
        for paths: [String],
        with configuration: Configuration
    ) -> ERScript
}

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
