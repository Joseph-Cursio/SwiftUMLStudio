/// Represents a single import relationship between a source module and the module it imports.
public struct ImportEdge: Sendable, Hashable {
    /// The parent directory name of the source file (used as module name heuristic).
    public let sourceModule: String

    /// The module name from the `import` statement.
    public let importedModule: String

    public init(sourceModule: String, importedModule: String) {
        self.sourceModule = sourceModule
        self.importedModule = importedModule
    }
}
