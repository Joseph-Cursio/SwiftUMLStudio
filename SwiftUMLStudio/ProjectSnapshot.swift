import Foundation
import SwiftData

@Model
final class ProjectSnapshot {
    var identifier: UUID
    var timestamp: Date?
    var typeCount: Int
    var relationshipCount: Int
    var moduleCount: Int
    var fileCount: Int
    var typeBreakdown: Data?
    var topConnectedTypes: Data?
    var projectPaths: Data?
    /// JSON-encoded `[Data?]` of security-scoped bookmarks aligned with
    /// `projectPaths`. Populated alongside paths when the user opens a folder
    /// via `NSOpenPanel`; `nil` on legacy rows.
    var projectPathBookmarks: Data?

    init(
        identifier: UUID = UUID(),
        timestamp: Date? = nil,
        typeCount: Int = 0,
        relationshipCount: Int = 0,
        moduleCount: Int = 0,
        fileCount: Int = 0,
        typeBreakdown: Data? = nil,
        topConnectedTypes: Data? = nil,
        projectPaths: Data? = nil,
        projectPathBookmarks: Data? = nil
    ) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.typeCount = typeCount
        self.relationshipCount = relationshipCount
        self.moduleCount = moduleCount
        self.fileCount = fileCount
        self.typeBreakdown = typeBreakdown
        self.topConnectedTypes = topConnectedTypes
        self.projectPaths = projectPaths
        self.projectPathBookmarks = projectPathBookmarks
    }

    /// Decoded type breakdown dictionary.
    var decodedTypeBreakdown: [String: Int] {
        guard let data = typeBreakdown else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    /// Decoded top connected types as name-count pairs.
    var decodedTopConnectedTypes: [(name: String, connectionCount: Int)] {
        guard let data = topConnectedTypes else { return [] }
        let pairs = (try? JSONDecoder().decode([[String: Int]].self, from: data)) ?? []
        return pairs.compactMap { dict in
            guard let entry = dict.first else { return nil }
            return (name: entry.key, connectionCount: entry.value)
        }
    }

    /// Decoded project paths.
    var decodedProjectPaths: [String] {
        guard let data = projectPaths else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Decoded bookmarks aligned with `decodedProjectPaths`. Each element may
    /// be `nil` when the bookmark couldn't be created at save time.
    var decodedProjectPathBookmarks: [Data?] {
        guard let data = projectPathBookmarks else { return [] }
        return (try? JSONDecoder().decode([Data?].self, from: data)) ?? []
    }
}
