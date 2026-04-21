import Foundation

/// A single attribute on an ER entity (e.g., a stored property on a SwiftData `@Model` class).
public struct ERAttribute: Sendable, Hashable {
    public let name: String
    public let type: String
    public let isOptional: Bool
    public let isPrimaryKey: Bool
    public let isUnique: Bool
    public let isTransient: Bool

    public init(
        name: String,
        type: String,
        isOptional: Bool = false,
        isPrimaryKey: Bool = false,
        isUnique: Bool = false,
        isTransient: Bool = false
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.isPrimaryKey = isPrimaryKey
        self.isUnique = isUnique
        self.isTransient = isTransient
    }
}

/// An ER entity — one persisted type (SwiftData `@Model`, Core Data entity, etc.).
public struct EREntity: Sendable, Hashable {
    public let name: String
    public let attributes: [ERAttribute]

    public init(name: String, attributes: [ERAttribute] = []) {
        self.name = name
        self.attributes = attributes
    }
}

/// Cardinality of an endpoint of an ER relationship.
public enum ERCardinality: String, Sendable, Hashable {
    /// Optional to-one (e.g., `var author: Author?`).
    case zeroOrOne
    /// Required to-one (e.g., `var author: Author`).
    case exactlyOne
    /// Optional to-many (e.g., `var books: [Book]` — empty collection is valid).
    case zeroOrMany
    /// Required to-many (rare in SwiftData; reserved for emitters that want to
    /// distinguish "must have at least one" from zero-or-many).
    case oneOrMany
}

/// A relationship edge between two ER entities.
///
/// Both endpoints carry a cardinality, so the emitter can render crow's-foot
/// style connectors (`||--o{`, `}o--||`, etc.) without re-deriving them.
public struct ERRelationship: Sendable, Hashable {
    public let from: String
    public let toEntity: String
    public let fromCardinality: ERCardinality
    public let toCardinality: ERCardinality
    public let label: String
    public let inverseLabel: String?

    public init(
        from: String,
        toEntity: String,
        fromCardinality: ERCardinality,
        toCardinality: ERCardinality,
        label: String,
        inverseLabel: String? = nil
    ) {
        self.from = from
        self.toEntity = toEntity
        self.fromCardinality = fromCardinality
        self.toCardinality = toCardinality
        self.label = label
        self.inverseLabel = inverseLabel
    }
}

/// A whole-project ER model — the IR that sits between the extractor and the emitters.
public struct ERModel: Sendable, Hashable {
    public let entities: [EREntity]
    public let relationships: [ERRelationship]

    public init(entities: [EREntity] = [], relationships: [ERRelationship] = []) {
        self.entities = entities
        self.relationships = relationships
    }

    /// True when no entities were discovered in the sources.
    public var isEmpty: Bool { entities.isEmpty }
}
