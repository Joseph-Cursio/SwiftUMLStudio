import Foundation

/// Options which relationships to show and how to style them in a class diagram
public struct RelationshipOptions: Codable, Sendable {
    public init(
        inheritance: Relationship? = Relationship(label: "inherits"),
        realize: Relationship? = Relationship(label: "conforms to"),
        dependency: Relationship? = Relationship(label: "ext")
    ) {
        self.inheritance = inheritance
        self.realize = realize
        self.dependency = dependency
    }

    /// The subclass-to-superclass inheritance edge, or `nil` to omit it.
    public var inheritance: Relationship? = Relationship(label: "inherits")
    /// The type-to-protocol conformance ("realize") edge, or `nil` to omit it.
    public var realize: Relationship? = Relationship(label: "conforms to")
    /// The extension-to-base-type dependency edge, or `nil` to omit it.
    public var dependency: Relationship? = Relationship(label: "ext")
}

/// Relationship metadata on if/how to visualize them in a class diagram
public struct Relationship: Codable, Sendable {
    public init(label: String? = nil, style: RelationshipStyle? = nil, exclude: [String]? = nil) {
        self.label = label
        self.style = style
        self.exclude = exclude
    }

    /// The text drawn on the edge, or `nil` for an unlabelled edge.
    public var label: String?
    /// The line and arrowhead style for the edge, or `nil` for the format default.
    public var style: RelationshipStyle?
    /// Name patterns whose edges of this kind are suppressed.
    public var exclude: [String]?
}
