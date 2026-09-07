import Foundation

/// Shared protocol for any diagram output (class diagram, sequence diagram, etc.).
/// Used by the GUI layer (DiagramWebView) and presenter layer to avoid type coupling.
public protocol DiagramOutputting: Sendable {
    var text: String { get }
    var format: DiagramFormat { get }
    func encodeText() -> String

    /// Positioned layout graph (available when format is `.svg`).
    var layoutGraph: LayoutGraph? { get }

    /// Positioned sequence layout (available for sequence diagrams when format is `.svg`).
    var sequenceLayout: SequenceLayout? { get }

    /// Positioned activity layout (available for activity diagrams when format is `.svg`).
    var activityLayout: ActivityLayout? { get }

    /// Positioned component layout (available for component diagrams when format is `.svg`).
    var componentLayout: ComponentLayout? { get }
}

/// Default implementations: the shared text encoding, and nil for the optional
/// layout data.
public extension DiagramOutputting {
    /// Encode the diagram text for PlantUML URL embedding.
    ///
    /// Every conformer spelled this the same way — seven copies of one line.
    /// A conformer that needs a different encoding still overrides it.
    func encodeText() -> String {
        DiagramText(rawValue: text).encodedValue
    }


    var layoutGraph: LayoutGraph? { nil }
    var sequenceLayout: SequenceLayout? { nil }
    var activityLayout: ActivityLayout? { nil }
    var componentLayout: ComponentLayout? { nil }
}

extension DiagramScript: DiagramOutputting {}
