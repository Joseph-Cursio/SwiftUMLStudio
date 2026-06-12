import Foundation

/// Renders a positioned `LayoutGraph` as an SVG XML string.
public struct SVGRenderer: Sendable {

    // MARK: - Colors

    private static let headerFill: [String: String] = [
        "class": "#4A90D9",
        "struct": "#7B68EE",
        "enum": "#E8A838",
        "protocol": "#50C878",
        "actor": "#E06666",
        "extension": "#999999",
        "macro": "#CC66CC"
    ]
    private static let bodyFill = "#FAFAFA"
    private static let strokeColor = "#333333"
    private static let textColor = "#FFFFFF"
    private static let bodyTextColor = "#333333"
    private static let fontSize: Double = 12
    private static let headerFontSize: Double = 13
    private static let lineHeight: Double = 18
    private static let padding: Double = 10
    private static let headerHeight: Double = 36
    private static let cornerRadius: Double = 4

    // MARK: - Public API

    /// Render the positioned layout graph to an SVG string.
    public static func render(_ graph: LayoutGraph) -> String {
        let margin: Double = 20
        let svgWidth = graph.width + margin * 2
        let svgHeight = graph.height + margin * 2

        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(svgWidth))" height="\(Int(svgHeight))" \
        viewBox="0 0 \(Int(svgWidth)) \(Int(svgHeight))" \
        style="font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;">
        <defs>
            \(arrowMarkers())
        </defs>
        """

        // Render module cluster boxes first (behind everything)
        for cluster in graph.clusters {
            svg += renderCluster(cluster)
        }

        // Render edges (behind nodes)
        for edge in graph.edges {
            svg += renderEdge(edge)
        }

        // Render nodes
        for node in graph.nodes {
            svg += renderNode(node)
        }

        svg += "\n</svg>"
        return svg
    }

    // MARK: - Arrow Markers

    private static func arrowMarkers() -> String {
        """
        <marker id="arrow-inheritance" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="12" markerHeight="12" orient="auto-start-reverse">
            <path d="M 0 0 L 12 6 L 0 12 Z" fill="white" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        <marker id="arrow-realization" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="12" markerHeight="12" orient="auto-start-reverse">
            <path d="M 0 0 L 12 6 L 0 12 Z" fill="white" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        <marker id="arrow-dependency" viewBox="0 0 12 12" refX="12" refY="6" \
        markerWidth="10" markerHeight="10" orient="auto-start-reverse">
            <path d="M 0 2 L 10 6 L 0 10" fill="none" stroke="\(strokeColor)" stroke-width="1.5"/>
        </marker>
        <marker id="arrow-composition" viewBox="0 0 16 12" refX="16" refY="6" \
        markerWidth="14" markerHeight="10" orient="auto-start-reverse">
            <path d="M 0 6 L 8 0 L 16 6 L 8 12 Z" fill="\(strokeColor)" stroke="\(strokeColor)" stroke-width="1"/>
        </marker>
        """
    }

    // MARK: - Node Rendering

    private static func renderNode(_ node: LayoutNode) -> String {
        let leftX = node.posX - node.width / 2
        let topY = node.posY - node.height / 2
        let stereotype = node.stereotype ?? "class"
        let fill = headerFill[stereotype] ?? headerFill["class"]!

        var svg = "\n<!-- \(node.label.xmlEscaped) -->\n"
        svg += "<g>\n"

        // Background rect with rounded corners
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(node.height))\" "
        svg += "rx=\"\(cornerRadius)\" ry=\"\(cornerRadius)\" "
        svg += "fill=\"\(bodyFill)\" stroke=\"\(strokeColor)\" stroke-width=\"1.5\"/>\n"

        // Header background
        let headerH = min(headerHeight, node.height)
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(headerH))\" "
        svg += "rx=\"\(cornerRadius)\" ry=\"\(cornerRadius)\" "
        svg += "fill=\"\(fill)\"/>\n"

        // Square off the bottom corners of the header when there are compartments
        if !node.compartments.isEmpty || node.height > headerHeight {
            svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY + headerH - cornerRadius))\" "
            svg += "width=\"\(fmt(node.width))\" height=\"\(fmt(cornerRadius))\" "
            svg += "fill=\"\(fill)\"/>\n"
        }

        // Stereotype label
        let stereotypeY = topY + 14
        svg += "  <text x=\"\(fmt(node.posX))\" y=\"\(fmt(stereotypeY))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" "
        svg += "font-size=\"10\" font-style=\"italic\">"
        svg += "&#x00AB;\(stereotype.xmlEscaped)&#x00BB;</text>\n"

        // Name label
        let nameY = topY + 28
        svg += "  <text x=\"\(fmt(node.posX))\" y=\"\(fmt(nameY))\" "
        svg += "text-anchor=\"middle\" fill=\"\(textColor)\" "
        svg += "font-size=\"\(headerFontSize)\" font-weight=\"bold\">"
        svg += "\(node.label.xmlEscaped)</text>\n"

        // Compartments
        var currentY = topY + headerH
        for compartment in node.compartments where !compartment.items.isEmpty {
            // Separator line
            svg += "  <line x1=\"\(fmt(leftX))\" y1=\"\(fmt(currentY))\" "
            svg += "x2=\"\(fmt(leftX + node.width))\" y2=\"\(fmt(currentY))\" "
            svg += "stroke=\"\(strokeColor)\" stroke-width=\"0.5\"/>\n"

            currentY += padding
            for item in compartment.items {
                currentY += lineHeight
                svg += "  <text x=\"\(fmt(leftX + padding))\" y=\"\(fmt(currentY - 4))\" "
                svg += "fill=\"\(bodyTextColor)\" font-size=\"\(fontSize)\">"
                svg += "\(item.xmlEscaped)</text>\n"
            }
            currentY += padding
        }

        svg += "</g>\n"
        return svg
    }

    // MARK: - Cluster Rendering

    /// Renders a module grouping box: a tinted, rounded rectangle with the
    /// module name in the top-left corner. The hue is derived deterministically
    /// from the module name so the same module keeps its color across renders
    /// (mirrors `NativeDiagramGeometry.moduleColor(for:)` in the Studio app).
    private static func renderCluster(_ cluster: LayoutCluster) -> String {
        let leftX = cluster.posX - cluster.width / 2
        let topY = cluster.posY - cluster.height / 2
        let hue = moduleHue(for: cluster.id)
        let color = "hsl(\(hue), 55%, 60%)"

        var svg = "\n<!-- module: \(cluster.label.xmlEscaped) -->\n"
        svg += "<g>\n"
        svg += "  <rect x=\"\(fmt(leftX))\" y=\"\(fmt(topY))\" "
        svg += "width=\"\(fmt(cluster.width))\" height=\"\(fmt(cluster.height))\" "
        svg += "rx=\"\(cornerRadius * 2)\" ry=\"\(cornerRadius * 2)\" "
        svg += "fill=\"\(color)\" fill-opacity=\"0.10\" "
        svg += "stroke=\"\(color)\" stroke-width=\"1.5\" stroke-dasharray=\"6,3\"/>\n"
        svg += "  <text x=\"\(fmt(leftX + padding))\" y=\"\(fmt(topY + 16))\" "
        svg += "fill=\"\(color)\" font-size=\"12\" font-weight=\"bold\">"
        svg += "\(cluster.label.xmlEscaped)</text>\n"
        svg += "</g>\n"
        return svg
    }

    /// Deterministic hue (0–359) for a module name — sums the name's unicode
    /// scalars mod 360, matching the Studio canvas color derivation.
    private static func moduleHue(for module: String) -> Int {
        let hash = module.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return ((hash % 360) + 360) % 360
    }

    // MARK: - Edge Rendering

    private static func renderEdge(_ edge: LayoutEdge) -> String {
        guard edge.points.count >= 2 else { return "" }

        let markerId: String
        let dashArray: String
        switch edge.style {
        case .inheritance:
            markerId = "arrow-inheritance"
            dashArray = ""
        case .realization:
            markerId = "arrow-realization"
            dashArray = " stroke-dasharray=\"6,3\""
        case .dependency:
            markerId = "arrow-dependency"
            dashArray = " stroke-dasharray=\"4,3\""
        case .association:
            markerId = ""
            dashArray = ""
        case .composition:
            markerId = "arrow-composition"
            dashArray = ""
        }

        var svg = ""

        // Build path from points
        let first = edge.points[0]
        var pathData = "M \(fmt(first.posX)) \(fmt(first.posY))"
        for point in edge.points.dropFirst() {
            pathData += " L \(fmt(point.posX)) \(fmt(point.posY))"
        }

        svg += "<path d=\"\(pathData)\" fill=\"none\" stroke=\"\(strokeColor)\" "
        svg += "stroke-width=\"1.2\"\(dashArray)"
        if !markerId.isEmpty {
            svg += " marker-end=\"url(#\(markerId))\""
        }
        svg += "/>\n"

        // Edge label
        if let label = edge.label, !label.isEmpty, edge.points.count >= 2 {
            let mid = edge.points[edge.points.count / 2]
            svg += "<text x=\"\(fmt(mid.posX + 4))\" y=\"\(fmt(mid.posY - 4))\" "
            svg += "fill=\"\(bodyTextColor)\" font-size=\"10\">"
            svg += "\(label.xmlEscaped)</text>\n"
        }

        return svg
    }

    // MARK: - Helpers

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
