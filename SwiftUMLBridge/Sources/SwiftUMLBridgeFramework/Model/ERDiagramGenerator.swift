import Foundation

/// Generates Entity-Relationship diagram scripts from Swift source files
/// and/or Core Data `.xcdatamodeld` bundles.
///
/// Paths ending in `.xcdatamodeld` are dispatched to `CoreDataModelExtractor`;
/// other paths fall through the SwiftData `@Model` path. Both contribute to
/// the same merged `ERModel` so a project that mixes the two stacks renders
/// a single diagram. GRDB schemas are deferred to a follow-up commit.
public struct ERDiagramGenerator: ERDiagramGenerating, @unchecked Sendable {
    public init() {}

    public func generateScript(
        for paths: [String],
        with configuration: Configuration = .default
    ) -> ERScript {
        var entities: [EREntity] = []
        var relationships: [ERRelationship] = []
        var seenEntity = Set<String>()
        var seenRelationship = Set<String>()

        // Step 1 — peel off any Core Data bundles in the input paths.
        let (coreDataBundles, swiftSourcePaths) = partitionCoreDataBundles(paths)

        for bundle in coreDataBundles {
            guard let model = try? CoreDataModelExtractor.extract(from: bundle) else { continue }
            mergeIn(model, entities: &entities, relationships: &relationships,
                    seenEntity: &seenEntity, seenRelationship: &seenRelationship)
        }

        // Step 2 — fall through to Swift-source parsing. Each file is
        // examined by both ERModelExtractor (SwiftData @Model) and
        // PersistenceSchemaExtractor (GRDB). The two extractors look for
        // mutually-exclusive signals so a file is only ever an entity in one
        // of them; running both per file is simpler than trying to predict
        // which one applies. Skipping the pass entirely when there are no
        // Swift sources avoids FileCollector's empty-paths fallback, which
        // walks the cwd and overflows the stack under sandboxed test hosts.
        if !swiftSourcePaths.isEmpty {
            let files = FileCollector().getFiles(for: swiftSourcePaths)
            for file in files {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let swiftDataModel = ERModelExtractor.extract(from: source)
                mergeIn(swiftDataModel, entities: &entities, relationships: &relationships,
                        seenEntity: &seenEntity, seenRelationship: &seenRelationship)

                let grdbModel = PersistenceSchemaExtractor.extract(from: source)
                mergeIn(grdbModel, entities: &entities, relationships: &relationships,
                        seenEntity: &seenEntity, seenRelationship: &seenRelationship)
            }
        }

        let merged = ERModel(entities: entities, relationships: relationships)
        guard !merged.isEmpty else { return .empty }
        return ERScript(model: merged, configuration: configuration)
    }

    /// Split the input path list into `(.xcdatamodeld bundles, everything else)`.
    /// A `.xcdatamodeld` is a directory bundle on disk, so we test the suffix.
    private func partitionCoreDataBundles(_ paths: [String]) -> (bundles: [URL], swiftPaths: [String]) {
        var bundles: [URL] = []
        var swiftPaths: [String] = []
        for path in paths {
            if path.hasSuffix(".xcdatamodeld") {
                bundles.append(URL(fileURLWithPath: path))
            } else {
                swiftPaths.append(path)
            }
        }
        return (bundles, swiftPaths)
    }

    private func mergeIn(
        _ model: ERModel,
        entities: inout [EREntity],
        relationships: inout [ERRelationship],
        seenEntity: inout Set<String>,
        seenRelationship: inout Set<String>
    ) {
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

    /// Canonical key for an edge — order-independent so a relationship
    /// rediscovered from an `.xcdatamodeld` follow-up won't duplicate the
    /// SwiftData-discovered one.
    private func relationshipKey(_ relationship: ERRelationship) -> String {
        let ends = [relationship.from, relationship.toEntity].sorted()
        return "\(ends[0])|\(ends[1])|\(relationship.label)|\(relationship.inverseLabel ?? "")"
    }
}
