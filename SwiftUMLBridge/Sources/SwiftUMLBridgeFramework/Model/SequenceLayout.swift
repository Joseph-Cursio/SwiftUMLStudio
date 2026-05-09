import Foundation

// MARK: - Sequence Layout Model

/// Positioned layout data for a sequence diagram, ready for native rendering.
public struct SequenceLayout: Sendable {
    public var participants: [SequenceParticipant]
    public var messages: [SequenceMessage]
    public var title: String
    public var totalWidth: Double
    public var totalHeight: Double
    public var lifelineStartY: Double
    public var lifelineEndY: Double

    public init(
        participants: [SequenceParticipant] = [],
        messages: [SequenceMessage] = [],
        title: String = "",
        totalWidth: Double = 0,
        totalHeight: Double = 0,
        lifelineStartY: Double = 0,
        lifelineEndY: Double = 0
    ) {
        self.participants = participants
        self.messages = messages
        self.title = title
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
        self.lifelineStartY = lifelineStartY
        self.lifelineEndY = lifelineEndY
    }
}

// MARK: - Sequence Participant

/// A participant box in a sequence diagram with its positioned column.
public struct SequenceParticipant: Identifiable, Sendable {
    public let id: String
    public let name: String
    public var centerX: Double
    public var topY: Double
    public var width: Double
    public var height: Double
    public var bottomTopY: Double

    /// Where the type backing this participant is declared in the source, when
    /// known. Populated by `SequenceSVGRenderer.computeLayout` from the
    /// `typeLocations` map handed in by `SequenceDiagramGenerator`.
    public var sourceLocation: SourceLocation?

    public init(
        name: String,
        centerX: Double = 0,
        topY: Double = 0,
        width: Double = 120,
        height: Double = 36,
        bottomTopY: Double = 0,
        sourceLocation: SourceLocation? = nil
    ) {
        self.id = name
        self.name = name
        self.centerX = centerX
        self.topY = topY
        self.width = width
        self.height = height
        self.bottomTopY = bottomTopY
        self.sourceLocation = sourceLocation
    }
}

// MARK: - Sequence Message

/// A message arrow in a sequence diagram.
public struct SequenceMessage: Identifiable, Sendable {
    public let id: Int
    public let label: String
    public let fromX: Double
    public let toX: Double
    public var posY: Double
    public let isAsync: Bool
    public let isUnresolved: Bool
    public let noteText: String?

    public init(
        id: Int,
        label: String,
        fromX: Double,
        toX: Double,
        posY: Double,
        isAsync: Bool = false,
        isUnresolved: Bool = false,
        noteText: String? = nil
    ) {
        self.id = id
        self.label = label
        self.fromX = fromX
        self.toX = toX
        self.posY = posY
        self.isAsync = isAsync
        self.isUnresolved = isUnresolved
        self.noteText = noteText
    }
}
