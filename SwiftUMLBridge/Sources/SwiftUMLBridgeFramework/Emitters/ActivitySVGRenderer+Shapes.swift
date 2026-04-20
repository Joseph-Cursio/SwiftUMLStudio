import Foundation

/// SVG shape and edge rendering helpers for `ActivitySVGRenderer`.
extension ActivitySVGRenderer {

    // MARK: - Node rendering

    static func renderNode(_ node: PositionedActivityNode) -> String {
        switch node.kind {
        case .start:
            return renderCircle(
                centerX: node.centerX, centerY: node.centerY,
                radius: node.width / 2, fill: terminalFill, stroke: strokeColor
            )
        case .end:
            return renderCircle(
                centerX: node.centerX, centerY: node.centerY,
                radius: node.width / 2, fill: "#FFFFFF", stroke: strokeColor
            ) + renderCircle(
                centerX: node.centerX, centerY: node.centerY,
                radius: node.width / 2 - 5, fill: terminalFill, stroke: terminalFill
            )
        case .action:
            let fill = node.isAsync ? asyncActionFill : actionFill
            return renderRoundedRect(node: node, fill: fill) + renderCenteredText(node: node)
        case .decision, .loopStart:
            return renderDiamond(node: node, fill: decisionFill) + renderCenteredText(node: node)
        case .merge, .loopEnd:
            return renderDiamond(node: node, fill: mergeFill)
        case .fork, .join:
            return renderBar(node: node, fill: forkJoinFill)
        }
    }

    static func renderCircle(
        centerX: Double, centerY: Double, radius: Double, fill: String, stroke: String
    ) -> String {
        "<circle cx=\"\(fmt(centerX))\" cy=\"\(fmt(centerY))\" r=\"\(fmt(radius))\" " +
        "fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>\n"
    }

    static func renderRoundedRect(node: PositionedActivityNode, fill: String) -> String {
        let leftX = node.centerX - node.width / 2
        let topY = node.centerY - node.height / 2
        return "<rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" " +
               "width=\"\(fmt(node.width))\" height=\"\(fmt(node.height))\" rx=\"8\" ry=\"8\" " +
               "fill=\"\(fill)\" stroke=\"\(strokeColor)\" stroke-width=\"1.5\"/>\n"
    }

    static func renderDiamond(node: PositionedActivityNode, fill: String) -> String {
        let centerX = node.centerX, centerY = node.centerY
        let halfW = node.width / 2, halfH = node.height / 2
        let points = "\(fmt(centerX)),\(fmt(centerY - halfH)) " +
                     "\(fmt(centerX + halfW)),\(fmt(centerY)) " +
                     "\(fmt(centerX)),\(fmt(centerY + halfH)) " +
                     "\(fmt(centerX - halfW)),\(fmt(centerY))"
        return "<polygon points=\"\(points)\" fill=\"\(fill)\" " +
               "stroke=\"\(strokeColor)\" stroke-width=\"1.5\"/>\n"
    }

    static func renderBar(node: PositionedActivityNode, fill: String) -> String {
        let leftX = node.centerX - node.width / 2
        let topY = node.centerY - node.height / 2
        return "<rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" " +
               "width=\"\(fmt(node.width))\" height=\"\(fmt(node.height))\" " +
               "fill=\"\(fill)\" stroke=\"\(strokeColor)\" stroke-width=\"1\"/>\n"
    }

    static func renderCenteredText(node: PositionedActivityNode) -> String {
        let label = escapeXML(node.label)
        return "<text x=\"\(fmt(node.centerX))\" y=\"\(fmt(node.centerY + 4))\" " +
               "text-anchor=\"middle\" font-size=\"11\" fill=\"\(bodyTextColor)\">\(label)</text>\n"
    }

    // MARK: - Edge rendering

    static func renderEdge(edge: ActivityEdge, layout: ActivityLayout) -> String {
        guard let source = layout.node(withId: edge.fromId),
              let target = layout.node(withId: edge.toId) else { return "" }

        if target.centerY <= source.centerY {
            return renderBackEdge(from: source, to: target, label: edge.label)
        }
        return renderForwardEdge(from: source, to: target, label: edge.label)
    }

    static func renderForwardEdge(
        from source: PositionedActivityNode,
        to target: PositionedActivityNode,
        label: String?
    ) -> String {
        let startY = source.centerY + source.height / 2
        let endY = target.centerY - target.height / 2
        let startX = source.centerX
        let endX = target.centerX

        var svg = "<line x1=\"\(fmt(startX))\" y1=\"\(fmt(startY))\" " +
                  "x2=\"\(fmt(endX))\" y2=\"\(fmt(endY))\" " +
                  "stroke=\"\(strokeColor)\" stroke-width=\"1.2\" marker-end=\"url(#act-arrow)\"/>\n"

        if let label, !label.isEmpty {
            let midX = (startX + endX) / 2
            let midY = (startY + endY) / 2 - 4
            svg += "<text x=\"\(fmt(midX))\" y=\"\(fmt(midY))\" text-anchor=\"middle\" " +
                   "font-size=\"10\" fill=\"\(bodyTextColor)\" font-style=\"italic\">" +
                   "\(escapeXML(label))</text>\n"
        }
        return svg
    }

    static func renderBackEdge(
        from source: PositionedActivityNode,
        to target: PositionedActivityNode,
        label: String?
    ) -> String {
        let startX = source.centerX + source.width / 2
        let startY = source.centerY
        let endX = target.centerX + target.width / 2
        let endY = target.centerY
        let detourX = max(startX, endX) + 30

        let path = "M \(fmt(startX)) \(fmt(startY)) " +
                   "L \(fmt(detourX)) \(fmt(startY)) " +
                   "L \(fmt(detourX)) \(fmt(endY)) " +
                   "L \(fmt(endX)) \(fmt(endY))"
        var svg = "<path d=\"\(path)\" fill=\"none\" stroke=\"\(strokeColor)\" " +
                  "stroke-width=\"1.2\" stroke-dasharray=\"4,3\" marker-end=\"url(#act-arrow)\"/>\n"

        if let label, !label.isEmpty {
            svg += "<text x=\"\(fmt(detourX + 4))\" y=\"\(fmt((startY + endY) / 2))\" " +
                   "text-anchor=\"start\" font-size=\"10\" fill=\"\(bodyTextColor)\" " +
                   "font-style=\"italic\">\(escapeXML(label))</text>\n"
        }
        return svg
    }
}
