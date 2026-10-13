import Foundation
import SwiftData

@Model
final class DiagramEntity {
    var identifier: UUID
    var mode: String?
    /// The Format picker's value when the diagram was saved — restores the picker.
    var format: String?
    /// The format `scriptText` is actually written in, which differs from `format` when the
    /// Bridge fell back to another language (state in `.svg` emits Mermaid, component in
    /// `.nomnoml` emits PlantUML). Optional and additive: entities saved before this was
    /// recorded have `nil` here and fall back to `format`.
    var scriptFormat: String?
    var entryPoint: String?
    var sequenceDepth: Int
    var paths: Data?
    /// JSON-encoded `[Data?]` of security-scoped bookmarks, one per entry in
    /// `paths`. Optional and additive: legacy entities saved before sandbox
    /// adoption have `nil` here and fall back to raw paths (read-access only
    /// restored if the user re-grants via NSOpenPanel).
    var pathBookmarks: Data?
    var scriptText: String?
    var timestamp: Date?
    var name: String?

    init(
        identifier: UUID = UUID(),
        mode: String? = nil,
        format: String? = nil,
        scriptFormat: String? = nil,
        entryPoint: String? = nil,
        sequenceDepth: Int = 0,
        paths: Data? = nil,
        pathBookmarks: Data? = nil,
        scriptText: String? = nil,
        timestamp: Date? = nil,
        name: String? = nil
    ) {
        self.identifier = identifier
        self.mode = mode
        self.format = format
        self.scriptFormat = scriptFormat
        self.entryPoint = entryPoint
        self.sequenceDepth = sequenceDepth
        self.paths = paths
        self.pathBookmarks = pathBookmarks
        self.scriptText = scriptText
        self.timestamp = timestamp
        self.name = name
    }

    /// Decoded bookmarks aligned with `decodedPaths`. Each element may be `nil`
    /// (the bookmark couldn't be created at save time) or unresolvable later
    /// (the file was moved or deleted) — callers should treat both as a signal
    /// to fall back to the raw path and accept that read access may be denied
    /// under sandbox.
    var decodedPathBookmarks: [Data?] {
        guard let data = pathBookmarks else { return [] }
        return (try? JSONDecoder().decode([Data?].self, from: data)) ?? []
    }
}
