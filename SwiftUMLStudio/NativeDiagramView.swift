import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for class and dependency diagrams.
/// Draws from a positioned `LayoutGraph` with pan, zoom, and hover support.
struct NativeDiagramView: View {
    let graph: LayoutGraph
    let viewport: DiagramViewport

    @State private var hoveredNodeId: String?

    private static let canvasCoordinateSpace = "nativeDiagramCanvas"

    // MARK: - Colors

    private static let bodyFill = SwiftUI.Color(white: 0.98)
    private static let strokeColor = SwiftUI.Color(white: 0.2)
    private static let selectedStrokeColor = SwiftUI.Color.accentColor
    private static let headerTextColor = SwiftUI.Color.white
    private static let bodyTextColor = SwiftUI.Color(white: 0.2)

    // MARK: - Layout Constants (forwarded to NativeDiagramGeometry)

    private static let headerHeight = NativeDiagramGeometry.headerHeight
    private static let lineHeight = NativeDiagramGeometry.lineHeight
    private static let padding = NativeDiagramGeometry.padding
    private static let cornerRadius = NativeDiagramGeometry.cornerRadius

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(graph.width + 40, Double(geometry.size.width))
            let canvasHeight = max(graph.height + 40, Double(geometry.size.height))

            Canvas { context, _ in
                for edge in graph.edges {
                    drawEdge(edge, in: &context)
                }
                for node in graph.nodes {
                    let isHovered = hoveredNodeId == node.id
                    let isSelected = viewport.selectedNodeId == node.id
                    drawNode(node, isHovered: isHovered, isSelected: isSelected, in: &context)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .coordinateSpace(name: Self.canvasCoordinateSpace)
            .scaleEffect(viewport.scale)
            .offset(viewport.offset)
            .gesture(magnificationGesture)
            .gesture(dragGesture)
            .gesture(tapToSelectGesture)
            .onTapGesture(count: 2) { viewport.reset() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Class diagram canvas")
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier("nativeDiagramCanvas")
            .onAppear {
                viewport.contentSize = CGSize(width: graph.width, height: graph.height)
                viewport.visibleSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewport.visibleSize = newSize
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in viewport.updateScale(magnification: value.magnification) }
            .onEnded { _ in viewport.commitScale() }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in viewport.updateOffset(translation: value.translation) }
            .onEnded { _ in viewport.commitOffset() }
    }

    private var tapToSelectGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.canvasCoordinateSpace))
            .onEnded { value in
                viewport.selectedNodeId =
                    NativeDiagramGeometry.hitNode(in: graph, at: value.location)?.id
            }
    }

    // MARK: - Node Drawing

    private func drawNode(
        _ node: LayoutNode, isHovered: Bool, isSelected: Bool, in context: inout GraphicsContext
    ) {
        let stereotype = node.stereotype ?? "class"
        let color = NativeDiagramGeometry.headerColor(for: stereotype)
        let rect = NativeDiagramGeometry.nodeRect(for: node)
        let headerRect = NativeDiagramGeometry.headerRect(for: node)

        drawNodeBox(rect: rect, headerRect: headerRect, color: color,
                    hasCompartments: !node.compartments.isEmpty, in: &context)
        if isSelected {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2),
                                cornerRadius: Self.cornerRadius + 2),
                           with: .color(Self.selectedStrokeColor), lineWidth: 3)
        } else if isHovered {
            context.stroke(Path(roundedRect: rect, cornerRadius: Self.cornerRadius),
                           with: .color(Self.strokeColor), lineWidth: 2.5)
        }
        drawNodeLabels(node: node, topY: rect.minY, stereotype: stereotype, in: &context)
        drawNodeCompartments(node: node, leftX: rect.minX,
                             startY: rect.minY + headerRect.height, in: &context)
    }

    private func drawNodeBox(
        rect: CGRect, headerRect: CGRect, color: SwiftUI.Color,
        hasCompartments: Bool, in context: inout GraphicsContext
    ) {
        let rounded = Path(roundedRect: rect, cornerRadius: Self.cornerRadius)
        context.fill(rounded, with: .color(Self.bodyFill))

        let bottom: CGFloat = hasCompartments ? 0 : Self.cornerRadius
        let headerPath = Path { path in
            path.addRoundedRect(in: headerRect, cornerRadii: RectangleCornerRadii(
                topLeading: Self.cornerRadius, bottomLeading: bottom,
                bottomTrailing: bottom, topTrailing: Self.cornerRadius
            ))
        }
        context.fill(headerPath, with: .color(color))
        context.stroke(rounded, with: .color(Self.strokeColor), lineWidth: 1.5)
    }

    private func drawNodeLabels(
        node: LayoutNode, topY: Double, stereotype: String,
        in context: inout GraphicsContext
    ) {
        let stereoText = Text("\u{00AB}\(stereotype)\u{00BB}")
            .font(.system(size: 10, design: .default).italic())
            .foregroundStyle(Self.headerTextColor)
        context.draw(stereoText, at: CGPoint(x: node.posX, y: topY + 12), anchor: .center)

        let nameText = Text(node.label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Self.headerTextColor)
        context.draw(nameText, at: CGPoint(x: node.posX, y: topY + 27), anchor: .center)
    }

    private func drawNodeCompartments(
        node: LayoutNode, leftX: Double, startY: Double,
        in context: inout GraphicsContext
    ) {
        var currentY = startY
        for compartment in node.compartments where !compartment.items.isEmpty {
            var separatorPath = Path()
            separatorPath.move(to: CGPoint(x: leftX, y: currentY))
            separatorPath.addLine(to: CGPoint(x: leftX + node.width, y: currentY))
            context.stroke(separatorPath, with: .color(Self.strokeColor.opacity(0.4)),
                           lineWidth: 0.5)

            currentY += Self.padding
            for item in compartment.items {
                currentY += Self.lineHeight
                let itemText = Text(item)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Self.bodyTextColor)
                context.draw(itemText,
                             at: CGPoint(x: leftX + Self.padding, y: currentY - 4),
                             anchor: .bottomLeading)
            }
            currentY += Self.padding
        }
    }

    // MARK: - Edge Drawing

    private func drawEdge(_ edge: LayoutEdge, in context: inout GraphicsContext) {
        guard edge.points.count >= 2 else { return }

        var path = Path()
        let first = edge.points[0]
        path.move(to: CGPoint(x: first.posX, y: first.posY))
        for point in edge.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.posX, y: point.posY))
        }

        let strokeStyle = NativeDiagramGeometry.strokeStyle(for: edge.style)

        context.stroke(path, with: .color(Self.strokeColor), style: strokeStyle)

        // Draw arrowhead at the last point
        if edge.points.count >= 2 {
            let lastPoint = edge.points[edge.points.count - 1]
            let prevPoint = edge.points[edge.points.count - 2]
            drawArrowhead(
                at: CGPoint(x: lastPoint.posX, y: lastPoint.posY),
                from: CGPoint(x: prevPoint.posX, y: prevPoint.posY),
                style: edge.style,
                in: &context
            )
        }

        // Draw label
        if let label = edge.label, !label.isEmpty {
            let mid = edge.points[edge.points.count / 2]
            let labelText = Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Self.bodyTextColor)
            context.draw(labelText, at: CGPoint(x: mid.posX + 4, y: mid.posY - 6), anchor: .bottomLeading)
        }
    }

    private func drawArrowhead(
        at tip: CGPoint, from prev: CGPoint, style: EdgeStyle, in context: inout GraphicsContext
    ) {
        let points = NativeDiagramGeometry.arrowheadPoints(tip: tip, prev: prev)

        switch style {
        case .inheritance, .realization:
            var path = Path()
            path.move(to: tip); path.addLine(to: points.left); path.addLine(to: points.right); path.closeSubpath()
            context.fill(path, with: .color(.white))
            context.stroke(path, with: .color(Self.strokeColor), lineWidth: 1)
        case .dependency:
            var path = Path()
            path.move(to: points.left); path.addLine(to: tip); path.addLine(to: points.right)
            context.stroke(path, with: .color(Self.strokeColor), lineWidth: 1.5)
        case .composition:
            let angle = atan2(tip.y - prev.y, tip.x - prev.x)
            drawDiamond(at: tip, angle: angle, in: &context)
        case .association:
            break
        }
    }

    private func drawDiamond(
        at tip: CGPoint, angle: CGFloat, in context: inout GraphicsContext
    ) {
        let points = NativeDiagramGeometry.diamondPoints(
            tip: tip, angle: angle,
            length: NativeDiagramGeometry.arrowLength,
            width: NativeDiagramGeometry.arrowWidth
        )
        var path = Path()
        path.move(to: points.tip)
        path.addLine(to: points.left)
        path.addLine(to: points.far)
        path.addLine(to: points.right)
        path.closeSubpath()
        context.fill(path, with: .color(Self.strokeColor))
    }
}
