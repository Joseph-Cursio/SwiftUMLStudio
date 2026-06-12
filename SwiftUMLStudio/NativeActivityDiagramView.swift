import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for activity diagrams.
/// Draws from a positioned `ActivityLayout` with pan and zoom.
struct NativeActivityDiagramView: View {
    let layout: ActivityLayout
    let viewport: DiagramViewport

    // MARK: - Colors

    /// Strokes + edge arrows — adapts to system label color.
    private static let strokeColor = SwiftUI.Color(nsColor: .labelColor).opacity(0.7)
    /// Action labels + edge labels — adapts to system text color.
    private static let bodyTextColor = SwiftUI.Color(nsColor: .labelColor)
    /// Saturated pastels for action / decision shapes — stay the same in both
    /// modes; legibility is preserved by the dark stroke around them.
    private static let actionFill = SwiftUI.Color(red: 0.89, green: 0.95, blue: 0.99)
    private static let asyncActionFill = SwiftUI.Color(red: 0.93, green: 0.91, blue: 0.96)
    private static let decisionFill = SwiftUI.Color(red: 1.0, green: 0.98, blue: 0.77)
    /// Start / end / fork / join markers — adaptive so they stay visible in
    /// dark mode (the previous near-black fill disappeared into the dark bg).
    private static let terminalFill = SwiftUI.Color(nsColor: .labelColor)
    private static let forkJoinFill = SwiftUI.Color(nsColor: .labelColor)
    /// Inner ring of the end marker — matches the canvas bg so the "ring"
    /// effect works in both modes.
    private static let mergeFill = SwiftUI.Color(nsColor: .textBackgroundColor)

    var body: some View {
        DiagramCanvasContainer(
            viewport: viewport,
            contentSize: CGSize(width: layout.totalWidth, height: layout.totalHeight),
            accessibilityLabel: "Activity diagram canvas",
            accessibilityIdentifier: "nativeActivityCanvas"
        ) { context in
            DiagramDrawing.drawTitle(
                layout.title, centerX: layout.totalWidth / 2,
                color: Self.bodyTextColor, in: &context
            )
            drawEdges(in: &context)
            drawNodes(in: &context)
        }
    }

    // MARK: - Drawing

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
        let rect = node.boundingRect
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
        let rect = node.boundingRect
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

        DiagramDrawing.fillArrowhead(
            at: endPoint,
            direction: CGPoint(x: endPoint.x - startPoint.x, y: endPoint.y - startPoint.y),
            color: Self.strokeColor,
            in: &context
        )

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

        DiagramDrawing.fillArrowhead(
            at: endPoint, direction: CGPoint(x: -1, y: 0), color: Self.strokeColor, in: &context
        )

        if let label, !label.isEmpty {
            let labelPoint = CGPoint(x: detourX + 6, y: (startPoint.y + endPoint.y) / 2)
            let text = Text(label)
                .font(.system(size: 10).italic())
                .foregroundStyle(Self.bodyTextColor)
            context.draw(text, at: labelPoint, anchor: .leading)
        }
    }

}
