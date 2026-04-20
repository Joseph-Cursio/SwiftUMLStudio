import CoreGraphics
import SwiftUI
import SwiftUMLBridgeFramework

/// Pure geometry helpers for `NativeSequenceDiagramView` — separated from the
/// Canvas draw calls so the math is unit-testable.
nonisolated enum NativeSequenceGeometry {

    // MARK: - Message classification

    /// Two messages are considered a self-call loop when the from/to X coordinates
    /// are within 1 point of each other.
    static func isSelfLoop(message: SequenceMessage) -> Bool {
        abs(message.fromX - message.toX) < 1
    }

    /// Whether the arrowhead for a horizontal message should point left.
    static func arrowPointsLeft(from: Double, toX: Double) -> Bool {
        toX < from
    }

    // MARK: - Stroke styling

    static func arrowStrokeStyle(isAsync: Bool) -> StrokeStyle {
        isAsync
            ? StrokeStyle(lineWidth: 1.2, dash: [4, 3])
            : StrokeStyle(lineWidth: 1.2)
    }

    // MARK: - Label positioning

    /// Midpoint between two X coordinates — used to center a message label
    /// above its arrow.
    static func labelMidX(from: Double, toX: Double) -> Double {
        (from + toX) / 2
    }

    // MARK: - Self-loop geometry

    struct SelfLoop: Equatable {
        let start: CGPoint
        let top: CGPoint
        let bottom: CGPoint
        let returnPoint: CGPoint
        let labelOrigin: CGPoint
    }

    static let selfLoopWidth: CGFloat = 30
    static let selfLoopHeight: CGFloat = 20

    /// Compute the four anchor points that form a self-loop ⟲ and the label
    /// origin to the right of the loop.
    static func selfLoop(at fromX: Double, posY: Double) -> SelfLoop {
        let start = CGPoint(x: fromX, y: posY)
        let top = CGPoint(x: fromX + selfLoopWidth, y: posY)
        let bottom = CGPoint(x: fromX + selfLoopWidth, y: posY + selfLoopHeight)
        let returnPoint = CGPoint(x: fromX, y: posY + selfLoopHeight)
        let labelOrigin = CGPoint(x: fromX + selfLoopWidth + 4, y: posY + selfLoopHeight / 2)
        return SelfLoop(
            start: start, top: top, bottom: bottom,
            returnPoint: returnPoint, labelOrigin: labelOrigin
        )
    }

    // MARK: - Arrow-tip geometry

    static let smallArrowSize: CGFloat = 8

    struct SmallArrowPoints: Equatable {
        let tip: CGPoint
        let upper: CGPoint
        let lower: CGPoint
    }

    /// Three vertices of a small triangular arrowhead at `point`.
    /// `pointingLeft == true` places the triangle's open base to the right of `point`.
    static func smallArrowPoints(
        at point: CGPoint, pointingLeft: Bool, size: CGFloat = smallArrowSize
    ) -> SmallArrowPoints {
        let direction: CGFloat = pointingLeft ? 1 : -1
        return SmallArrowPoints(
            tip: point,
            upper: CGPoint(
                x: point.x + direction * size,
                y: point.y - size / 2
            ),
            lower: CGPoint(
                x: point.x + direction * size,
                y: point.y + size / 2
            )
        )
    }

    // MARK: - Note geometry

    static let noteHeight: Double = 24

    /// Width of a note box sized to fit `text` with a minimum of 100 points.
    static func noteWidth(for text: String) -> Double {
        max(Double(text.count) * 7, 100)
    }

    /// Note bounding rect centered on `(centerX, posY)`.
    static func noteRect(text: String, centerX: Double, posY: Double) -> CGRect {
        let width = noteWidth(for: text)
        return CGRect(
            x: centerX - width / 2,
            y: posY - noteHeight / 2,
            width: width,
            height: noteHeight
        )
    }
}
