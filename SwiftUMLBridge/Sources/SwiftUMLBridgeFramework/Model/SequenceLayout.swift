import Foundation

// MARK: - Sequence Layout Model

/// Positioned layout data for a sequence diagram, ready for native rendering.
public struct SequenceLayout: Sendable {
    /// The positioned participant columns, left to right.
    public var participants: [SequenceParticipant]
    /// The positioned message arrows, top to bottom.
    public var messages: [SequenceMessage]
    /// The diagram title drawn above the participants.
    public var title: String
    /// The total canvas width, in points.
    public var totalWidth: Double
    /// The total canvas height, in points.
    public var totalHeight: Double
    /// The Y coordinate where the participant lifelines begin.
    public var lifelineStartY: Double
    /// The Y coordinate where the participant lifelines end.
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
    /// Stable identity for the participant; equal to ``name``.
    public let id: String
    /// The participant's display name (the backing type name).
    public let name: String
    /// The X coordinate of the participant box's horizontal center.
    public var centerX: Double
    /// The Y coordinate of the top participant box.
    public var topY: Double
    /// The participant box width, in points.
    public var width: Double
    /// The participant box height, in points.
    public var height: Double
    /// The Y coordinate of the mirrored bottom participant box.
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
    /// Stable identity for the message; its order index in the trace.
    public let id: Int
    /// The call label drawn on the arrow (typically the method name).
    public let label: String
    /// The X coordinate of the sending participant's lifeline.
    public let fromX: Double
    /// The X coordinate of the receiving participant's lifeline.
    public let toX: Double
    /// The Y coordinate at which the arrow is drawn.
    public var posY: Double
    /// Whether the call is asynchronous (drawn with an open arrowhead).
    public let isAsync: Bool
    /// Whether the callee could not be resolved to a known participant.
    public let isUnresolved: Bool
    /// Optional note text attached to the message, when present.
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
