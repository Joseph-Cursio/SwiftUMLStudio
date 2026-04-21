import Foundation

/// Generates Entity-Relationship diagram scripts from Swift source files.
///
/// Parsing covers SwiftData `@Model` classes. Core Data `.xcdatamodeld`
/// bundles and GRDB schemas are deferred to follow-up commits.
public struct ERDiagramGenerator: ERDiagramGenerating, @unchecked Sendable {
    public init() {}

    public func generateScript(
        for paths: [String],
        with configuration: Configuration = .default
    ) -> ERScript {
        let files = FileCollector().getFiles(for: paths)
        var entities: [EREntity] = []
        var relationships: [ERRelationship] = []
        var seenEntity = Set<String>()
        var seenRelationship = Set<String>()

        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let model = ERModelExtractor.extract(from: source)
            for entity in model.entities where !seenEntity.contains(entity.name) {
                seenEntity.insert(entity.name)
                entities.append(entity)
            }
            for relationship in model.relationships {
                let key = relationshipKey(relationship)
                if !seenRelationship.contains(key) {
                    seenRelationship.insert(key)
                    relationships.append(relationship)
                }
            }
        }

        let merged = ERModel(entities: entities, relationships: relationships)
        guard !merged.isEmpty else { return .empty }
        return ERScript(model: merged, configuration: configuration)
    }

    /// Canonical key for an edge — order-independent so a relationship
    /// rediscovered from an `.xcdatamodeld` follow-up won't duplicate the
    /// SwiftData-discovered one.
    private func relationshipKey(_ relationship: ERRelationship) -> String {
        let ends = [relationship.from, relationship.toEntity].sorted()
        return "\(ends[0])|\(ends[1])|\(relationship.label)|\(relationship.inverseLabel ?? "")"
    }
}
