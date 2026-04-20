import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for activity diagrams.
/// Draws from a positioned `ActivityLayout` with pan and zoom.
struct NativeActivityDiagramView: View {
    let layout: ActivityLayout

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - Colors

    private static let strokeColor = SwiftUI.Color(white: 0.2)
    private static let bodyTextColor = SwiftUI.Color(white: 0.2)
    private static let actionFill = SwiftUI.Color(red: 0.89, green: 0.95, blue: 0.99)
    private static let asyncActionFill = SwiftUI.Color(red: 0.93, green: 0.91, blue: 0.96)
    private static let decisionFill = SwiftUI.Color(red: 1.0, green: 0.98, blue: 0.77)
    private static let terminalFill = SwiftUI.Color(white: 0.2)
    private static let forkJoinFill = SwiftUI.Color(white: 0.2)
    private static let mergeFill = SwiftUI.Color.white

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(layout.totalWidth + 40, Double(geometry.size.width))
            let canvasHeight = max(layout.totalHeight + 40, Double(geometry.size.height))

            Canvas { context, _ in
                drawTitle(in: &context)
                drawEdges(in: &context)
                drawNodes(in: &context)
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
            .accessibilityLabel("Activity diagram canvas")
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier("nativeActivityCanvas")
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = lastScale * value.magnification }
            .onEnded { value in
                lastScale *= value.magnification
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
            .onEnded { _ in lastOffset = offset }
    }

    // MARK: - Drawing

    private func drawTitle(in context: inout GraphicsContext) {
        guard !layout.title.isEmpty else { return }
        let titleText = Text(layout.title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Self.bodyTextColor)
        context.draw(titleText, at: CGPoint(x: layout.totalWidth / 2, y: 18), anchor: .center)
    }

    private func drawNodes(in context: inout GraphicsContext) {
        for node in layout.nodes {
            switch node.kind {
            case .start:
                drawCircle(center: CGPoint(x: node.centerX, y: node.centerY),
                           radius: node.width / 2, fill: Self.terminalFill, in: &context)
            case .end:
                drawCircle(center: CGPoint(x: node.centerX, y: node.centerY),
                           radius: node.width / 2, fill: Self.mergeFill, in: &context)
                drawCircle(center: CGPoint(x: node.centerX, y: node.centerY),
                           radius: node.width / 2 - 5, fill: Self.terminalFill, in: &context)
            case .action:
                let fill = node.isAsync ? Self.asyncActionFill : Self.actionFill
                drawRoundedRect(node: node, fill: fill, in: &context)
                drawLabel(node: node, in: &context)
            case .decision, .loopStart:
                drawDiamond(node: node, fill: Self.decisionFill, in: &context)
                drawLabel(node: node, in: &context)
            case .merge, .loopEnd:
                drawDiamond(node: node, fill: Self.mergeFill, in: &context)
            case .fork, .join:
                drawBar(node: node, fill: Self.forkJoinFill, in: &context)
            }
        }
    }

    private func drawCircle(
        center: CGPoint, radius: Double,
        fill: SwiftUI.Color, in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.fill(Path(ellipseIn: rect), with: .color(fill))
        context.stroke(Path(ellipseIn: rect), with: .color(Self.strokeColor), lineWidth: 1.5)
    }

    private func drawRoundedRect(
        node: PositionedActivityNode, fill: SwiftUI.Color, in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: node.centerX - node.width / 2, y: node.centerY - node.height / 2,
            width: node.width, height: node.height
        )
        context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(fill))
        context.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Self.strokeColor), lineWidth: 1.5)
    }

    private func drawDiamond(
        node: PositionedActivityNode, fill: SwiftUI.Color, in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: node.centerX, y: node.centerY - node.height / 2))
        path.addLine(to: CGPoint(x: node.centerX + node.width / 2, y: node.centerY))
        path.addLine(to: CGPoint(x: node.centerX, y: node.centerY + node.height / 2))
        path.addLine(to: CGPoint(x: node.centerX - node.width / 2, y: node.centerY))
        path.closeSubpath()
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(Self.strokeColor), lineWidth: 1.5)
    }

    private func drawBar(
        node: PositionedActivityNode, fill: SwiftUI.Color, in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: node.centerX - node.width / 2, y: node.centerY - node.height / 2,
            width: node.width, height: node.height
        )
        context.fill(Path(rect), with: .color(fill))
        context.stroke(Path(rect), with: .color(Self.strokeColor), lineWidth: 1)
    }

    private func drawLabel(
        node: PositionedActivityNode, in context: inout GraphicsContext
    ) {
        guard !node.label.isEmpty else { return }
        let text = Text(node.label)
            .font(.system(size: 11))
            .foregroundStyle(Self.bodyTextColor)
        context.draw(text, at: CGPoint(x: node.centerX, y: node.centerY), anchor: .center)
    }

    private func drawEdges(in context: inout GraphicsContext) {
        for edge in layout.edges {
            guard let source = layout.node(withId: edge.fromId),
                  let target = layout.node(withId: edge.toId) else { continue }
            let isBackEdge = target.centerY <= source.centerY
            if isBackEdge {
                drawBackEdge(from: source, to: target, label: edge.label, in: &context)
            } else {
                drawForwardEdge(from: source, to: target, label: edge.label, in: &context)
            }
        }
    }

    private func drawForwardEdge(
        from source: PositionedActivityNode,
        to target: PositionedActivityNode,
        label: String?,
        in context: inout GraphicsContext
    ) {
        let startPoint = CGPoint(x: source.centerX, y: source.centerY + source.height / 2)
        let endPoint = CGPoint(x: target.centerX, y: target.centerY - target.height / 2)

        var path = Path()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        context.stroke(path, with: .color(Self.strokeColor), lineWidth: 1.2)

        drawArrowHead(at: endPoint, direction: CGPoint(x: endPoint.x - startPoint.x,
                                                       y: endPoint.y - startPoint.y), in: &context)

        if let label, !label.isEmpty {
            let labelPoint = CGPoint(
                x: (startPoint.x + endPoint.x) / 2,
                y: (startPoint.y + endPoint.y) / 2 - 6
            )
            let text = Text(label)
                .font(.system(size: 10).italic())
                .foregroundStyle(Self.bodyTextColor)
            context.draw(text, at: labelPoint, anchor: .center)
        }
    }

    private func drawBackEdge(
        from source: PositionedActivityNode,
        to target: PositionedActivityNode,
        label: String?,
        in context: inout GraphicsContext
    ) {
        let startPoint = CGPoint(x: source.centerX + source.width / 2, y: source.centerY)
        let endPoint = CGPoint(x: target.centerX + target.width / 2, y: target.centerY)
        let detourX = max(startPoint.x, endPoint.x) + 30

        var path = Path()
        path.move(to: startPoint)
        path.addLine(to: CGPoint(x: detourX, y: startPoint.y))
        path.addLine(to: CGPoint(x: detourX, y: endPoint.y))
        path.addLine(to: endPoint)
        context.stroke(
            path, with: .color(Self.strokeColor),
            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
        )

        drawArrowHead(at: endPoint, direction: CGPoint(x: -1, y: 0), in: &context)

        if let label, !label.isEmpty {
            let labelPoint = CGPoint(x: detourX + 6, y: (startPoint.y + endPoint.y) / 2)
            let text = Text(label)
                .font(.system(size: 10).italic())
                .foregroundStyle(Self.bodyTextColor)
            context.draw(text, at: labelPoint, anchor: .leading)
        }
    }

    private func drawArrowHead(
        at point: CGPoint, direction: CGPoint, in context: inout GraphicsContext
    ) {
        let length = max(hypot(direction.x, direction.y), 0.001)
        let unitX = direction.x / length
        let unitY = direction.y / length
        let size: CGFloat = 8
        let baseX = point.x - unitX * size
        let baseY = point.y - unitY * size
        let perpX = -unitY
        let perpY = unitX

        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: baseX + perpX * size / 2, y: baseY + perpY * size / 2))
        path.addLine(to: CGPoint(x: baseX - perpX * size / 2, y: baseY - perpY * size / 2))
        path.closeSubpath()
        context.fill(path, with: .color(Self.strokeColor))
    }
}
