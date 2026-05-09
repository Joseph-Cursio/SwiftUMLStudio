import Foundation

/// SQLite.swift schema container — a namespace type holding `Table` and
/// `Expression` declarations. The detector treats `Schema` itself as a
/// namespace (not an entity) and emits the `Table("users")` declaration as
/// the entity, with the sibling `Expression` columns attached.
public enum Schema {
    public static let users = Table("users")
    public static let id = Expression<Int64>("id")
    public static let name = Expression<String>("name")
    public static let email = Expression<String>("email")
}

/// Stand-ins so the fixture is self-contained for syntax purposes — the
/// extractor only reads the source via SwiftSyntax and never links against
/// SQLite.swift itself.
public struct Table {
    public init(_ name: String) {}
}

public struct Expression<T> {
    public init(_ name: String) {}
}
