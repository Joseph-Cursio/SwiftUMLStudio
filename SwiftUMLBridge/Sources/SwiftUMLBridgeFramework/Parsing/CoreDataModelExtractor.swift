import Foundation

/// Parses an `.xcdatamodeld` bundle into an `ERModel`.
///
/// The bundle is a directory containing one or more versioned
/// `.xcdatamodel` directories, each holding a `contents` XML file.
/// `.xccurrentversion` (a plist) names the active version. We pick the
/// active version when present; otherwise we fall back to the first
/// `.xcdatamodel` sibling.
public enum CoreDataModelExtractor {

    public enum ExtractionError: Error, Equatable {
        case noModelVersionFound(String)
        case missingContentsFile(String)
        case malformedContentsXML(String)
    }

    /// Extract an `ERModel` from a `.xcdatamodeld` bundle.
    public static func extract(from bundleURL: URL) throws -> ERModel {
        let activeContents = try resolveActiveContentsURL(bundleURL: bundleURL)
        return try parseContents(at: activeContents)
    }

    /// Locate the active `.xcdatamodel/contents` inside the bundle. Honors
    /// `.xccurrentversion` if present; otherwise picks the first
    /// `.xcdatamodel` directory in alphabetical order.
    static func resolveActiveContentsURL(bundleURL: URL) throws -> URL {
        let manager = FileManager.default
        let modelDirs = (try? manager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "xcdatamodel" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            ?? []
        guard !modelDirs.isEmpty else {
            throw ExtractionError.noModelVersionFound(bundleURL.path)
        }

        // Prefer the version named in .xccurrentversion when it exists and
        // points at one of the discovered model directories.
        let currentVersionPlist = bundleURL.appendingPathComponent(".xccurrentversion")
        if let data = try? Data(contentsOf: currentVersionPlist),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let activeName = plist["_XCCurrentVersionName"] as? String,
           let activeDir = modelDirs.first(where: { $0.lastPathComponent == activeName }) {
            return try contentsURL(in: activeDir)
        }

        return try contentsURL(in: modelDirs[0])
    }

    private static func contentsURL(in modelDirectory: URL) throws -> URL {
        let url = modelDirectory.appendingPathComponent("contents")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExtractionError.missingContentsFile(modelDirectory.path)
        }
        return url
    }

    /// Parse a single `contents` XML file into an `ERModel`.
    static func parseContents(at url: URL) throws -> ERModel {
        let document: XMLDocument
        do {
            document = try XMLDocument(contentsOf: url)
        } catch {
            throw ExtractionError.malformedContentsXML(error.localizedDescription)
        }

        guard let root = document.rootElement() else {
            throw ExtractionError.malformedContentsXML("missing root element")
        }

        var entities: [EREntity] = []
        var relationships: [ERRelationship] = []

        let entityNodes = (try? root.nodes(forXPath: "entity")) ?? []
        for case let entityElement as XMLElement in entityNodes {
            guard let name = entityElement.attribute(forName: "name")?.stringValue else { continue }

            let attributes = parseAttributes(in: entityElement)
            entities.append(EREntity(name: name, attributes: attributes))

            relationships.append(contentsOf: parseRelationships(in: entityElement, owner: name))

            if let parent = entityElement.attribute(forName: "parentEntity")?.stringValue,
               !parent.isEmpty {
                relationships.append(ERRelationship(
                    from: name, toEntity: parent,
                    fromCardinality: .zeroOrMany, toCardinality: .exactlyOne,
                    label: "is a", inverseLabel: nil
                ))
            }
        }

        let dedupedRelationships = dedupe(relationships: relationships)
        return ERModel(entities: entities, relationships: dedupedRelationships)
    }

    private static func parseAttributes(in entityElement: XMLElement) -> [ERAttribute] {
        let attributeNodes = (try? entityElement.nodes(forXPath: "attribute")) ?? []
        var result: [ERAttribute] = []
        for case let attribute as XMLElement in attributeNodes {
            guard let name = attribute.attribute(forName: "name")?.stringValue else { continue }
            let type = attribute.attribute(forName: "attributeType")?.stringValue ?? "Undefined"
            let isOptional = (attribute.attribute(forName: "optional")?.stringValue ?? "NO") == "YES"
            let isTransient = (attribute.attribute(forName: "transient")?.stringValue ?? "NO") == "YES"
            result.append(ERAttribute(
                name: name, type: type,
                isOptional: isOptional, isTransient: isTransient
            ))
        }
        return result
    }

    private static func parseRelationships(in entityElement: XMLElement, owner: String) -> [ERRelationship] {
        let relationshipNodes = (try? entityElement.nodes(forXPath: "relationship")) ?? []
        var result: [ERRelationship] = []
        for case let relationship as XMLElement in relationshipNodes {
            guard let name = relationship.attribute(forName: "name")?.stringValue,
                  let destination = relationship.attribute(forName: "destinationEntity")?.stringValue
            else { continue }
            let toMany = (relationship.attribute(forName: "toMany")?.stringValue ?? "NO") == "YES"
            let isOptional = (relationship.attribute(forName: "optional")?.stringValue ?? "NO") == "YES"
            let minCount = Int(relationship.attribute(forName: "minCount")?.stringValue ?? "") ?? 0
            let maxCount = Int(relationship.attribute(forName: "maxCount")?.stringValue ?? "") ?? 0
            let inverseName = relationship.attribute(forName: "inverseName")?.stringValue

            let toCardinality: ERCardinality
            if toMany {
                toCardinality = minCount > 0 ? .oneOrMany : .zeroOrMany
            } else if maxCount == 1 || maxCount == 0 {
                toCardinality = isOptional ? .zeroOrOne : .exactlyOne
            } else {
                toCardinality = .zeroOrMany
            }

            let fromCardinality: ERCardinality
            switch toCardinality {
            case .zeroOrMany, .oneOrMany:
                fromCardinality = .exactlyOne
            case .zeroOrOne, .exactlyOne:
                fromCardinality = .zeroOrMany
            }

            result.append(ERRelationship(
                from: owner, toEntity: destination,
                fromCardinality: fromCardinality, toCardinality: toCardinality,
                label: name, inverseLabel: inverseName
            ))
        }
        return result
    }

    /// Drops a relationship whose inverse already appears in the list, so each
    /// edge is emitted once rather than twice (Core Data declares both sides).
    private static func dedupe(relationships: [ERRelationship]) -> [ERRelationship] {
        var seen: Set<String> = []
        var result: [ERRelationship] = []
        for relationship in relationships {
            let endpoints = [relationship.from, relationship.toEntity].sorted()
            let labels = [relationship.label, relationship.inverseLabel ?? ""].sorted()
            let key = "\(endpoints[0])|\(endpoints[1])|\(labels[0])|\(labels[1])"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(relationship)
            }
        }
        return result
    }
}
