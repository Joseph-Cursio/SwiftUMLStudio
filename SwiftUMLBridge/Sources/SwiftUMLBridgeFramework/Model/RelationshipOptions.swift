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

    /// The subclass-to-superclass inheritance edge. `nil` draws these edges with no label or
    /// style; it does not hide them.
    public var inheritance: Relationship? = Relationship(label: "inherits")
    /// The type-to-protocol conformance ("realize") edge. `nil` draws these edges with no label
    /// or style; it does not hide them.
    public var realize: Relationship? = Relationship(label: "conforms to")
    /// The extension-to-base-type dependency edge. `nil` draws these edges with no style, and
    /// labelled `ext`; it does not hide them.
    public var dependency: Relationship? = Relationship(label: "ext")
}

extension RelationshipOptions {
    /// The patterns that hide an edge from a type to one of its supertypes: `inheritance` and
    /// `realize` excludes together. Which of the two an edge is drawn as depends on whether the
    /// diagram declares the parent: an undeclared protocol such as `Codable` is drawn as
    /// inheritance. So either list hides every supertype edge to a name it matches, and the documented
    /// `realize.exclude: [Codable, Sendable]` works (#113).
    var supertypeExcludePatterns: [String] {
        (inheritance?.exclude ?? []) + (realize?.exclude ?? [])
    }
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
    /// Glob patterns for names whose edges are hidden. For `inheritance` and `realize` they
    /// match the supertype's name as written, generic arguments included but not attributes
    /// or specifiers (`Sendable` for `@unchecked Sendable`), and the two lists are pooled
    /// (`supertypeExcludePatterns`). For `dependency` they match the extended
    /// type's name, and hide only the edge from an extension to that type.
    public var exclude: [String]?
}
