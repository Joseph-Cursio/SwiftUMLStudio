import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for sequence diagrams.
/// Draws from a positioned `SequenceLayout` with pan, zoom support.
struct NativeSequenceDiagramView: View {
    let layout: SequenceLayout
    let viewport: DiagramViewport

    private static let canvasCoordinateSpace = "nativeSequenceCanvas"

    // MARK: - Colors

    /// Saturated participant header — stays the same in both modes.
    private static let headerFill = SwiftUI.Color(red: 0.29, green: 0.56, blue: 0.85)
    /// Lifelines + arrows — adapts to system label color.
    private static let strokeColor = SwiftUI.Color(nsColor: .labelColor).opacity(0.7)
    /// Selection ring drawn around the selected participant box.
    private static let selectedStrokeColor = SwiftUI.Color.accentColor
    /// Stays white on the saturated header background.
    private static let headerTextColor = SwiftUI.Color.white
    /// Message labels and note text — adapts to system text color.
    private static let bodyTextColor = SwiftUI.Color(nsColor: .labelColor)
    /// Static yellow note background — readable in both modes.
    private static let noteFill = SwiftUI.Color(red: 1.0, green: 0.98, blue: 0.80)
    private static let noteStroke = SwiftUI.Color(red: 0.80, green: 0.80, blue: 0.53)

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(layout.totalWidth + 40, Double(geometry.size.width))
            let canvasHeight = max(layout.totalHeight + 40, Double(geometry.size.height))

            Canvas { context, _ in
                DiagramDrawing.drawTitle(
                    layout.title, centerX: layout.totalWidth / 2, topY: 14,
                    color: Self.bodyTextColor, in: &context
                )
                drawLifelines(in: &context)
                drawParticipantBoxes(top: true, in: &context)
                drawMessages(in: &context)
                drawParticipantBoxes(top: false, in: &context)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .coordinateSpace(name: Self.canvasCoordinateSpace)
            .canvasPanZoom(viewport: viewport)
            .gesture(tapToSelectGesture)
            .onTapGesture(count: 2) { viewport.reset() }
            .onContinuousHover(coordinateSpace: .named(Self.canvasCoordinateSpace)) { phase in
                switch phase {
                case .active(let location):
                    viewport.hoveredNodeId =
                        NativeSequenceGeometry.hitParticipant(in: layout, at: location)?.id
                case .ended:
                    viewport.hoveredNodeId = nil
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { handleArrow(.left) }
            .onKeyPress(.rightArrow) { handleArrow(.right) }
            .onKeyPress(.escape) {
                viewport.selectedNodeId = nil
                return .handled
            }
            .diagramCanvasChrome(
                viewport: viewport,
                contentSize: CGSize(width: layout.totalWidth, height: layout.totalHeight),
                visibleSize: geometry.size,
                label: "Sequence diagram canvas",
                identifier: "nativeSequenceCanvas"
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Gestures

    private var tapToSelectGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.canvasCoordinateSpace))
            .onEnded { value in
                viewport.selectedNodeId =
                    NativeSequenceGeometry.hitParticipant(in: layout, at: value.location)?.id
            }
    }

    private func handleArrow(_ direction: NativeDiagramGeometry.NavigationDirection) -> KeyPress.Result {
        if let currentId = viewport.selectedNodeId,
           let next = NativeSequenceGeometry.nextParticipant(
                in: layout, from: currentId, direction: direction
           ) {
            viewport.selectedNodeId = next.id
            return .handled
        }
        if let first = NativeSequenceGeometry.firstParticipant(in: layout) {
            viewport.selectedNodeId = first.id
            return .handled
        }
        return .ignored
    }

    // MARK: - Drawing

    private func drawLifelines(in context: inout GraphicsContext) {
        for participant in layout.participants {
            var path = Path()
            path.move(to: CGPoint(x: participant.centerX, y: layout.lifelineStartY))
            path.addLine(to: CGPoint(x: participant.centerX, y: layout.lifelineEndY))
            context.stroke(
                path,
                with: .color(Self.strokeColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
    }

    private func drawParticipantBoxes(top: Bool, in context: inout GraphicsContext) {
        for participant in layout.participants {
            let topY = top ? participant.topY : participant.bottomTopY
            let rect = CGRect(
                x: participant.centerX - participant.width / 2,
                y: topY,
                width: participant.width,
                height: participant.height
            )

            context.fill(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(Self.headerFill)
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(Self.strokeColor),
                lineWidth: 1.5
            )

            if viewport.selectedNodeId == participant.id {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 6),
                    with: .color(Self.selectedStrokeColor),
                    lineWidth: 3
                )
            } else if viewport.hoveredNodeId == participant.id {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 5),
                    with: .color(Self.strokeColor),
                    lineWidth: 2.5
                )
            }

            let nameText = Text(participant.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Self.headerTextColor)
            context.draw(
                nameText,
                at: CGPoint(x: participant.centerX, y: topY + participant.height / 2),
                anchor: .center
            )
        }
    }

    private func drawMessages(in context: inout GraphicsContext) {
        for message in layout.messages {
            if message.isUnresolved, let noteText = message.noteText {
                drawNote(text: noteText, centerX: message.toX, posY: message.posY, in: &context)
            } else {
                drawArrow(message: message, in: &context)
            }
        }
    }

    private func drawArrow(message: SequenceMessage, in context: inout GraphicsContext) {
        let strokeStyle = NativeSequenceGeometry.arrowStrokeStyle(isAsync: message.isAsync)

        if NativeSequenceGeometry.isSelfLoop(message: message) {
            drawSelfLoop(message: message, strokeStyle: strokeStyle, in: &context)
        } else {
            drawHorizontalArrow(message: message, strokeStyle: strokeStyle, in: &context)
        }
    }

    private func drawSelfLoop(
        message: SequenceMessage, strokeStyle: StrokeStyle, in context: inout GraphicsContext
    ) {
        let loop = NativeSequenceGeometry.selfLoop(at: message.fromX, posY: message.posY)
        var path = Path()
        path.move(to: loop.start)
        path.addLine(to: loop.top)
        path.addLine(to: loop.bottom)
        path.addLine(to: loop.returnPoint)
        context.stroke(path, with: .color(Self.strokeColor), style: strokeStyle)

        drawSmallArrow(
            at: loop.returnPoint,
            pointingLeft: true,
            filled: !message.isAsync,
            in: &context
        )

        let labelText = Text(message.label)
            .font(.system(size: 11))
            .foregroundStyle(Self.bodyTextColor)
        context.draw(labelText, at: loop.labelOrigin, anchor: .leading)
    }

    private func drawHorizontalArrow(
        message: SequenceMessage, strokeStyle: StrokeStyle, in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: CGPoint(x: message.fromX, y: message.posY))
        path.addLine(to: CGPoint(x: message.toX, y: message.posY))
        context.stroke(path, with: .color(Self.strokeColor), style: strokeStyle)

        let pointsLeft = NativeSequenceGeometry.arrowPointsLeft(from: message.fromX, toX: message.toX)
        drawSmallArrow(
            at: CGPoint(x: message.toX, y: message.posY),
            pointingLeft: pointsLeft,
            filled: !message.isAsync,
            in: &context
        )

        let labelX = NativeSequenceGeometry.labelMidX(from: message.fromX, toX: message.toX)
        let labelText = Text(message.label)
            .font(.system(size: 11))
            .foregroundStyle(Self.bodyTextColor)
        context.draw(labelText, at: CGPoint(x: labelX, y: message.posY - 6), anchor: .bottom)
    }

    private func drawSmallArrow(
        at point: CGPoint,
        pointingLeft: Bool,
        filled: Bool,
        in context: inout GraphicsContext
    ) {
        let points = NativeSequenceGeometry.smallArrowPoints(at: point, pointingLeft: pointingLeft)
        var path = Path()
        path.move(to: points.tip)
        path.addLine(to: points.upper)
        path.addLine(to: points.lower)
        path.closeSubpath()

        if filled {
            context.fill(path, with: .color(Self.strokeColor))
        } else {
            context.stroke(path, with: .color(Self.strokeColor), lineWidth: 1.5)
        }
    }

    private func drawNote(text: String, centerX: Double, posY: Double, in context: inout GraphicsContext) {
        let rect = NativeSequenceGeometry.noteRect(text: text, centerX: centerX, posY: posY)
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Self.noteFill))
        context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(Self.noteStroke), lineWidth: 1)

        let noteText = Text(text)
            .font(.system(size: 10).italic())
            .foregroundStyle(Self.bodyTextColor)
        context.draw(noteText, at: CGPoint(x: centerX, y: posY), anchor: .center)
    }
}
