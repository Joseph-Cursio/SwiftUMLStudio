import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for class and dependency diagrams.
/// Draws from a positioned `LayoutGraph` with pan, zoom, and hover support.
struct NativeDiagramView: View, SelectableDiagramCanvas {
    let graph: LayoutGraph
    let viewport: DiagramViewport

    private static let canvasCoordinateSpace = "nativeDiagramCanvas"

    // MARK: - Colors

    /// Body fill for class boxes — adapts to light/dark mode via NSColor.
    static let bodyFill = SwiftUI.Color(nsColor: .controlBackgroundColor)
    /// Border + separator strokes — adapts via NSColor.labelColor at reduced opacity.
    static let strokeColor = SwiftUI.Color(nsColor: .labelColor).opacity(0.7)
    /// Accent ring around the selected node.
    static let selectedStrokeColor = SwiftUI.Color.accentColor
    /// Stays white in both modes — drawn on saturated colored headers.
    static let headerTextColor = SwiftUI.Color.white
    /// Member labels (properties, methods) — adapts to system text color.
    static let bodyTextColor = SwiftUI.Color(nsColor: .labelColor)

    // MARK: - Layout Constants (forwarded to NativeDiagramGeometry)

    static let headerHeight = NativeDiagramGeometry.headerHeight
    static let lineHeight = NativeDiagramGeometry.lineHeight
    static let padding = NativeDiagramGeometry.padding
    static let cornerRadius = NativeDiagramGeometry.cornerRadius

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(graph.width + 40, Double(geometry.size.width))
            let canvasHeight = max(graph.height + 40, Double(geometry.size.height))

            Canvas { context, _ in
                for cluster in graph.clusters {
                    drawCluster(cluster, in: &context)
                }
                for edge in graph.edges {
                    drawEdge(edge, in: &context)
                }
                for node in graph.nodes {
                    let isHovered = viewport.hoveredNodeId == node.id
                    let isSelected = viewport.selectedNodeId == node.id
                    drawNode(node, isHovered: isHovered, isSelected: isSelected, in: &context)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .selectableCanvasInteraction(
                self, coordinateSpace: Self.canvasCoordinateSpace, arrows: [.upward, .down, .left, .right]
            )
            .diagramCanvasChrome(
                viewport: viewport,
                contentSize: CGSize(width: graph.width, height: graph.height),
                visibleSize: geometry.size,
                label: "Class diagram canvas",
                identifier: "nativeDiagramCanvas"
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Selection geometry

    func nodeID(at location: CGPoint) -> String? {
        NativeDiagramGeometry.hitNode(in: graph, at: location)?.id
    }

    func nodeID(after currentID: String, direction: NativeDiagramGeometry.NavigationDirection) -> String? {
        NativeDiagramGeometry.nextNode(in: graph, from: currentID, direction: direction)?.id
    }

    func firstNodeID() -> String? {
        NativeDiagramGeometry.firstNode(in: graph)?.id
    }
}
