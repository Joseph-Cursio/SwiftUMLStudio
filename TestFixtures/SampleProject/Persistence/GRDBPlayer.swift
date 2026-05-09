import Foundation

/// Canonical positive case for GRDB detection: a `struct` conforming to
/// `Codable` + GRDB's record protocols, with `belongsTo` / `hasMany`
/// associations declared as `static let` properties.
public struct Player: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var teamId: Int64?

    /// belongsTo Team — Player → Team, many ↔ one
    public static let team = belongsTo(Team.self)

    /// hasMany Score — Player → Score, one ↔ many
    public static let scores = hasMany(Score.self)
}

public struct Team: Codable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
}

public struct Score: Codable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var playerId: Int64
    public var value: Int

    /// belongsTo Player — Score → Player, many ↔ one
    public static let player = belongsTo(Player.self)
}

/// Stand-ins for GRDB protocols and association functions so the fixture
/// type-checks standalone (the test only runs the SwiftSyntax extractor on
/// the file content; nothing actually links against GRDB).
public protocol FetchableRecord {}
public protocol PersistableRecord {}
public protocol MutablePersistableRecord: PersistableRecord {}
public struct BelongsToAssociation<O, T> {}
public struct HasManyAssociation<O, T> {}
public struct HasOneAssociation<O, T> {}

public extension FetchableRecord {
    static func belongsTo<T>(_ type: T.Type) -> BelongsToAssociation<Self, T> { .init() }
    static func hasMany<T>(_ type: T.Type) -> HasManyAssociation<Self, T> { .init() }
    static func hasOne<T>(_ type: T.Type) -> HasOneAssociation<Self, T> { .init() }
}
