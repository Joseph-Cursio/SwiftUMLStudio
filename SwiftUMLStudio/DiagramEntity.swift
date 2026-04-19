import Foundation
import SwiftData

@Model
final class DiagramEntity {
    var identifier: UUID
    var mode: String?
    var format: String?
    var entryPoint: String?
    var sequenceDepth: Int
    var paths: Data?
    var scriptText: String?
    var timestamp: Date?
    var name: String?

    init(
        identifier: UUID = UUID(),
        mode: String? = nil,
        format: String? = nil,
        entryPoint: String? = nil,
        sequenceDepth: Int = 0,
        paths: Data? = nil,
        scriptText: String? = nil,
        timestamp: Date? = nil,
        name: String? = nil
    ) {
        self.identifier = identifier
        self.mode = mode
        self.format = format
        self.entryPoint = entryPoint
        self.sequenceDepth = sequenceDepth
        self.paths = paths
        self.scriptText = scriptText
        self.timestamp = timestamp
        self.name = name
    }
}
