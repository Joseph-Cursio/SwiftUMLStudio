import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for class and dependency diagrams.
/// Draws from a positioned `LayoutGraph` with pan, zoom, and hover support.
struct NativeDiagramView: View {
    let graph: LayoutGraph

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var hoveredNodeId: String?

    // MARK: - Colors

    private static let headerColors: [String: SwiftUI.Color] = [
        "class": SwiftUI.Color(red: 0.29, green: 0.56, blue: 0.85),
        "struct": SwiftUI.Color(red: 0.48, green: 0.41, blue: 0.93),
        "enum": SwiftUI.Color(red: 0.91, green: 0.66, blue: 0.22),
        "protocol": SwiftUI.Color(red: 0.31, green: 0.78, blue: 0.47),
        "actor": SwiftUI.Color(red: 0.88, green: 0.40, blue: 0.40),
        "extension": SwiftUI.Color.gray,
        "macro": SwiftUI.Color(red: 0.80, green: 0.40, blue: 0.80),
        "warning": SwiftUI.Color(red: 1.0, green: 0.8, blue: 0.8)
    ]

    private static let bodyFill = SwiftUI.Color(white: 0.98)
    private static let strokeColor = SwiftUI.Color(white: 0.2)
    private static let headerTextColor = SwiftUI.Color.white
    private static let bodyTextColor = SwiftUI.Color(white: 0.2)

    // MARK: - Layout Constants

    private static let headerHeight: CGFloat = 36
    private static let lineHeight: CGFloat = 18
    private static let padding: CGFloat = 10
    private static let cornerRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(graph.width + 40, Double(geometry.size.width))
            let canvasHeight = max(graph.height + 40, Double(geometry.size.height))

            Canvas { context, _ in
                // Draw edges first (behind nodes)
                for edge in graph.edges {
                    drawEdge(edge, in: &context)
                }
                // Draw nodes
                for node in graph.nodes {
                    let isHovered = hoveredNodeId == node.id
                    drawNode(node, isHovered: isHovered, in: &context)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture)
            .gesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Class diagram canvas")
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier("nativeDiagramCanvas")
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = lastScale * value.magnification
            }
            .onEnded { value in
                lastScale = lastScale * value.magnification
                scale = lastScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                lastOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
    }

    // MARK: - Node Drawing

    private func drawNode(_ node: LayoutNode, isHovered: Bool, in context: inout GraphicsContext) {
        let leftX = node.posX - node.width / 2
        let topY = node.posY - node.height / 2
        let stereotype = node.stereotype ?? "class"
        let headerColor = Self.headerColors[stereotype] ?? Self.headerColors["class"]!

        let fullRect = CGRect(x: leftX, y: topY, width: node.width, height: node.height)
        let headerH = min(Self.headerHeight, node.height)
        let headerRect = CGRect(x: leftX, y: topY, width: node.width, height: headerH)

        // Shadow when hovered
        if isHovered {
            var shadowContext = context
            shadowContext.addFilter(.shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2))
            shadowContext.fill(
                Path(roundedRect: fullRect, cornerRadius: Self.cornerRadius),
                with: .color(Self.bodyFill)
            )
        }

        // Body background
        context.fill(
            Path(roundedRect: fullRect, cornerRadius: Self.cornerRadius),
            with: .color(Self.bodyFill)
        )

        // Header background
        let headerPath = Path { path in
            path.addRoundedRect(
                in: headerRect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: Self.cornerRadius,
                    bottomLeading: node.compartments.isEmpty ? Self.cornerRadius : 0,
                    bottomTrailing: node.compartments.isEmpty ? Self.cornerRadius : 0,
                    topTrailing: Self.cornerRadius
                )
            )
        }
        context.fill(headerPath, with: .color(headerColor))

        // Border
        context.stroke(
            Path(roundedRect: fullRect, cornerRadius: Self.cornerRadius),
            with: .color(Self.strokeColor),
            lineWidth: isHovered ? 2.5 : 1.5
        )

        // Stereotype text
        let stereoText = Text("\u{00AB}\(stereotype)\u{00BB}")
            .font(.system(size: 10, design: .default).italic())
            .foregroundStyle(Self.headerTextColor)
        context.draw(stereoText, at: CGPoint(x: node.posX, y: topY + 12), anchor: .center)

        // Name text
        let nameText = Text(node.label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Self.headerTextColor)
        context.draw(nameText, at: CGPoint(x: node.posX, y: topY + 27), anchor: .center)

        // Compartments
        var currentY = topY + headerH
        for compartment in node.compartments where !compartment.items.isEmpty {
            // Separator line
            var separatorPath = Path()
            separatorPath.move(to: CGPoint(x: leftX, y: currentY))
            separatorPath.addLine(to: CGPoint(x: leftX + node.width, y: currentY))
            context.stroke(separatorPath, with: .color(Self.strokeColor.opacity(0.4)), lineWidth: 0.5)

            currentY += Self.padding
            for item in compartment.items {
                currentY += Self.lineHeight
                let itemText = Text(item)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Self.bodyTextColor)
                context.draw(
                    itemText,
                    at: CGPoint(x: leftX + Self.padding, y: currentY - 4),
                    anchor: .bottomLeading
                )
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

        let isDashed = edge.style == .realization || edge.style == .dependency
        let strokeStyle = isDashed
            ? StrokeStyle(lineWidth: 1.2, dash: [6, 3])
            : StrokeStyle(lineWidth: 1.2)

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
        at tip: CGPoint,
        from prev: CGPoint,
        style: EdgeStyle,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(tip.y - prev.y, tip.x - prev.x)
        let arrowLength: CGFloat = 12
        let arrowWidth: CGFloat = 6

        let leftAngle = angle + .pi - .pi / 6
        let rightAngle = angle + .pi + .pi / 6

        let leftPoint = CGPoint(
            x: tip.x + arrowLength * cos(leftAngle),
            y: tip.y + arrowLength * sin(leftAngle)
        )
        let rightPoint = CGPoint(
            x: tip.x + arrowLength * cos(rightAngle),
            y: tip.y + arrowLength * sin(rightAngle)
        )

        var arrowPath = Path()
        arrowPath.move(to: tip)
        arrowPath.addLine(to: leftPoint)
        arrowPath.addLine(to: rightPoint)
        arrowPath.closeSubpath()

        switch style {
        case .inheritance, .realization:
            // Closed triangle, white fill
            context.fill(arrowPath, with: .color(.white))
            context.stroke(arrowPath, with: .color(Self.strokeColor), lineWidth: 1)
        case .dependency:
            // Open arrow (just two lines)
            var openPath = Path()
            openPath.move(to: leftPoint)
            openPath.addLine(to: tip)
            openPath.addLine(to: rightPoint)
            context.stroke(openPath, with: .color(Self.strokeColor), lineWidth: 1.5)
        case .composition:
            // Filled diamond
            let midLeft = CGPoint(
                x: tip.x + arrowLength * cos(angle + .pi),
                y: tip.y + arrowLength * sin(angle + .pi)
            )
            let diamondLeft = CGPoint(
                x: midLeft.x + arrowWidth * cos(angle + .pi / 2),
                y: midLeft.y + arrowWidth * sin(angle + .pi / 2)
            )
            let diamondRight = CGPoint(
                x: midLeft.x + arrowWidth * cos(angle - .pi / 2),
                y: midLeft.y + arrowWidth * sin(angle - .pi / 2)
            )
            let farPoint = CGPoint(
                x: tip.x + arrowLength * 2 * cos(angle + .pi),
                y: tip.y + arrowLength * 2 * sin(angle + .pi)
            )
            var diamondPath = Path()
            diamondPath.move(to: tip)
            diamondPath.addLine(to: diamondLeft)
            diamondPath.addLine(to: farPoint)
            diamondPath.addLine(to: diamondRight)
            diamondPath.closeSubpath()
            context.fill(diamondPath, with: .color(Self.strokeColor))
        case .association:
            break
        }
    }
}
