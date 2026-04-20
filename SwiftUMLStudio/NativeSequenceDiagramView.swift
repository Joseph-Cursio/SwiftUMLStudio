import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for sequence diagrams.
/// Draws from a positioned `SequenceLayout` with pan, zoom support.
struct NativeSequenceDiagramView: View {
    let layout: SequenceLayout

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - Colors

    private static let headerFill = SwiftUI.Color(red: 0.29, green: 0.56, blue: 0.85)
    private static let strokeColor = SwiftUI.Color(white: 0.2)
    private static let headerTextColor = SwiftUI.Color.white
    private static let bodyTextColor = SwiftUI.Color(white: 0.2)
    private static let noteFill = SwiftUI.Color(red: 1.0, green: 0.98, blue: 0.80)
    private static let noteStroke = SwiftUI.Color(red: 0.80, green: 0.80, blue: 0.53)

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(layout.totalWidth + 40, Double(geometry.size.width))
            let canvasHeight = max(layout.totalHeight + 40, Double(geometry.size.height))

            Canvas { context, _ in
                drawTitle(in: &context)
                drawLifelines(in: &context)
                drawParticipantBoxes(top: true, in: &context)
                drawMessages(in: &context)
                drawParticipantBoxes(top: false, in: &context)
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
            .accessibilityLabel("Sequence diagram canvas")
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier("nativeSequenceCanvas")
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
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - Drawing

    private func drawTitle(in context: inout GraphicsContext) {
        let titleText = Text(layout.title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Self.bodyTextColor)
        context.draw(titleText, at: CGPoint(x: layout.totalWidth / 2, y: 14), anchor: .center)
    }

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
