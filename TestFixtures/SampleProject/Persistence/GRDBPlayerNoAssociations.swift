import Foundation

/// GRDB record with no relationships — verifies that a "table-only" type
/// still produces an entity with attributes (and zero relationships).
public struct StandalonePlayer: Codable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var nickname: String
    public var rank: Int
}
