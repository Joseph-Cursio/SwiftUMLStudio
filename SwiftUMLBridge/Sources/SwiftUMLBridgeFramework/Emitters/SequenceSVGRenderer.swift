import Foundation

/// Lays out and renders sequence diagrams as SVG without dagre.
/// Uses a simple timeline layout: participants as columns, messages as horizontal arrows.
public struct SequenceSVGRenderer: Sendable {

    // MARK: - Layout Constants

    private static let participantWidth: Double = 120
    private static let participantHeight: Double = 36
    private static let participantSpacing: Double = 180
    private static let messageSpacing: Double = 40
    private static let topMargin: Double = 20
    private static let leftMargin: Double = 30
    private static let bottomMargin: Double = 40
    private static let lifelineExtension: Double = 20

    // MARK: - Colors

    private static let headerFill = "#4A90D9"
    private static let strokeColor = "#333333"
    private static let textColor = "#FFFFFF"
    private static let bodyTextColor = "#333333"

    // MARK: - Layout Computation

    /// Compute the positioned layout for a sequence diagram.
    /// `typeLocations` is consulted (if non-empty) to stamp each participant's
    /// `sourceLocation` so the Studio app can support reveal-in-source on
    /// participant clicks.
    public static func computeLayout(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String,
        typeLocations: [String: SourceLocation] = [:]
    ) -> SequenceLayout {
        let participantNames = collectParticipants(from: traversedEdges, entryType: entryType)

        let totalWidth = leftMargin * 2 + Double(participantNames.count) * participantSpacing
        let messagesStartY = topMargin + participantHeight + 20
        let lifelinesEndY = messagesStartY + Double(traversedEdges.count) * messageSpacing + lifelineExtension
        let lifelineStartY = topMargin + participantHeight

        var participantX: [String: Double] = [:]
        for (idx, name) in participantNames.enumerated() {
            participantX[name] = leftMargin + Double(idx) * participantSpacing + participantSpacing / 2
        }

        let participants = participantNames.map { name in
            SequenceParticipant(
                name: name,
                centerX: participantX[name]!,
                topY: topMargin,
                width: participantWidth,
                height: participantHeight,
                bottomTopY: lifelinesEndY,
                sourceLocation: typeLocations[name]
            )
        }
        let messages = buildMessages(from: traversedEdges, participantX: participantX,
                                     entryType: entryType, startY: messagesStartY)

        return SequenceLayout(
            participants: participants, messages: messages,
            title: "\(entryType).\(entryMethod)", totalWidth: totalWidth,
            totalHeight: lifelinesEndY + participantHeight + bottomMargin,
            lifelineStartY: lifelineStartY, lifelineEndY: lifelinesEndY
        )
    }

    private static func collectParticipants(from edges: [CallEdge], entryType: String) -> [String] {
        var names: [String] = [entryType]
        for edge in edges {
            if !edge.isUnresolved, let calleeType = edge.calleeType, !names.contains(calleeType) {
                names.append(calleeType)
            }
        }
        return names
    }

    private static func buildMessages(
        from edges: [CallEdge], participantX: [String: Double], entryType: String, startY: Double
    ) -> [SequenceMessage] {
        var messages: [SequenceMessage] = []
        var currentY = startY
        var lastCallee = entryType
        for (idx, edge) in edges.enumerated() {
            if edge.isUnresolved {
                let noteX = participantX[lastCallee] ?? participantX[entryType]!
                messages.append(SequenceMessage(
                    id: idx, label: "\(edge.calleeMethod)()", fromX: noteX, toX: noteX + 60,
                    posY: currentY, isUnresolved: true, noteText: "Unresolved: \(edge.calleeMethod)()"
                ))
            } else if let calleeType = edge.calleeType {
                messages.append(SequenceMessage(
                    id: idx, label: "\(edge.calleeMethod)()",
                    fromX: participantX[edge.callerType] ?? leftMargin,
                    toX: participantX[calleeType] ?? leftMargin,
                    posY: currentY, isAsync: edge.isAsync
                ))
                lastCallee = calleeType
            }
            currentY += messageSpacing
        }
        return messages
    }

    // MARK: - SVG Rendering

    /// Render a sequence diagram from traversed call edges.
    public static func render(
        traversedEdges: [CallEdge],
        entryType: String,
        entryMethod: String
    ) -> String {
        let layout = computeLayout(
            traversedEdges: traversedEdges,
            entryType: entryType,
            entryMethod: entryMethod
        )
        return renderFromLayout(layout)
    }

    /// Render SVG from a pre-computed sequence layout.
    public static func renderFromLayout(_ layout: SequenceLayout) -> String {
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(layout.totalWidth))" height="\(Int(layout.totalHeight))" \
        viewBox="0 0 \(Int(layout.totalWidth)) \(Int(layout.totalHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            <marker id="seq-arrow" viewBox="0 0 10 10" refX="10" refY="5" \
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 Z" fill="\(strokeColor)"/>
            </marker>
            <marker id="seq-arrow-open" viewBox="0 0 10 10" refX="10" refY="5" \
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                <path d="M 0 1 L 9 5 L 0 9" fill="none" stroke="\(strokeColor)" stroke-width="1.5"/>
            </marker>
        </defs>

        """

        // Title
        svg += "<text x=\"\(Int(layout.totalWidth / 2))\" y=\"14\" text-anchor=\"middle\" "
        svg += "font-size=\"14\" font-weight=\"bold\" fill=\"\(bodyTextColor)\">"
        svg += "\(layout.title.xmlEscaped)</text>\n"

        // Participant boxes (top) and lifelines
        for participant in layout.participants {
            svg += renderParticipantBox(
                name: participant.name, centerX: participant.centerX, topY: participant.topY
            )
            // Lifeline
            svg += "<line x1=\"\(fmt(participant.centerX))\" y1=\"\(fmt(layout.lifelineStartY))\" "
            svg += "x2=\"\(fmt(participant.centerX))\" y2=\"\(fmt(layout.lifelineEndY))\" "
            svg += "stroke=\"\(strokeColor)\" stroke-width=\"1\" stroke-dasharray=\"4,3\"/>\n"
        }

        // Messages
        for message in layout.messages {
            if message.isUnresolved, let noteText = message.noteText {
                svg += renderNote(text: noteText, centerX: message.toX, posY: message.posY)
            } else {
                svg += renderMessage(
                    label: message.label, fromX: message.fromX, toX: message.toX,
                    posY: message.posY, isAsync: message.isAsync
                )
            }
        }

        // Participant boxes (bottom)
        for participant in layout.participants {
            svg += renderParticipantBox(
                name: participant.name, centerX: participant.centerX, topY: participant.bottomTopY
            )
        }

        svg += "\n</svg>"
        return svg
    }

    // MARK: - Component Rendering

    private static func renderParticipantBox(name: String, centerX: Double, topY: Double) -> String {
        let leftX = centerX - participantWidth / 2
        var svg = "<rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(participantWidth))\" height=\"\(fmt(participantHeight))\" "
        svg += "rx=\"4\" ry=\"4\" fill=\"\(headerFill)\" stroke=\"\(strokeColor)\" stroke-width=\"1.5\"/>\n"

        svg += "<text x=\"\(fmt(centerX))\" y=\"\(fmt(topY + participantHeight / 2 + 5))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" font-size=\"12\" font-weight=\"bold\">"
        svg += "\(name.xmlEscaped)</text>\n"

        return svg
    }

    private static func renderMessage(
        label: String,
        fromX: Double,
        toX: Double,
        posY: Double,
        isAsync: Bool
    ) -> String {
        let markerId = isAsync ? "seq-arrow-open" : "seq-arrow"
        let dashArray = isAsync ? " stroke-dasharray=\"4,3\"" : ""

        var svg = ""

        // Handle self-calls
        if abs(fromX - toX) < 1 {
            let loopWidth: Double = 30
            svg += "<path d=\"M \(fmt(fromX)) \(fmt(posY)) "
            svg += "L \(fmt(fromX + loopWidth)) \(fmt(posY)) "
            svg += "L \(fmt(fromX + loopWidth)) \(fmt(posY + 20)) "
            svg += "L \(fmt(fromX)) \(fmt(posY + 20))\" "
            svg += "fill=\"none\" stroke=\"\(strokeColor)\" stroke-width=\"1.2\"\(dashArray) "
            svg += "marker-end=\"url(#\(markerId))\"/>\n"

            svg += "<text x=\"\(fmt(fromX + loopWidth + 4))\" y=\"\(fmt(posY + 12))\" "
            svg += "fill=\"\(bodyTextColor)\" font-size=\"11\">"
            svg += "\(label.xmlEscaped)</text>\n"
        } else {
            svg += "<line x1=\"\(fmt(fromX))\" y1=\"\(fmt(posY))\" "
            svg += "x2=\"\(fmt(toX))\" y2=\"\(fmt(posY))\" "
            svg += "stroke=\"\(strokeColor)\" stroke-width=\"1.2\"\(dashArray) "
            svg += "marker-end=\"url(#\(markerId))\"/>\n"

            let labelX = (fromX + toX) / 2
            svg += "<text x=\"\(fmt(labelX))\" y=\"\(fmt(posY - 6))\" "
            svg += "text-anchor=\"middle\" fill=\"\(bodyTextColor)\" font-size=\"11\">"
            svg += "\(label.xmlEscaped)</text>\n"
        }

        return svg
    }

    private static func renderNote(text: String, centerX: Double, posY: Double) -> String {
        let noteWidth: Double = max(Double(text.count) * 7, 100)
        let noteHeight: Double = 24
        let leftX = centerX - noteWidth / 2

        var svg = "<rect x=\"\(fmt(leftX))\" y=\"\(fmt(posY - noteHeight / 2))\" "
        svg += "width=\"\(fmt(noteWidth))\" height=\"\(fmt(noteHeight))\" "
        svg += "rx=\"2\" ry=\"2\" fill=\"#FFFACD\" stroke=\"#CCCC88\" stroke-width=\"1\"/>\n"

        svg += "<text x=\"\(fmt(centerX))\" y=\"\(fmt(posY + 4))\" "
        svg += "text-anchor=\"middle\" fill=\"\(bodyTextColor)\" font-size=\"10\" font-style=\"italic\">"
        svg += "\(text.xmlEscaped)</text>\n"

        return svg
    }

    // MARK: - Helpers

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
