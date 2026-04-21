import Foundation

/// Generates Entity-Relationship diagram scripts from Swift source files.
///
/// The current implementation is a stub that always returns `ERScript.empty`.
/// SwiftData `@Model` extraction, Core Data `.xcdatamodeld` parsing, and the
/// Mermaid / PlantUML emitters land in follow-up commits.
public struct ERDiagramGenerator: ERDiagramGenerating, @unchecked Sendable {
    public init() {}

    public func generateScript(
        for paths: [String],
        with configuration: Configuration = .default
    ) -> ERScript {
        .empty
    }
}
