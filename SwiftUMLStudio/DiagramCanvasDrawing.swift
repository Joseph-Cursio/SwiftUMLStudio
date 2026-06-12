import SwiftUI
import SwiftUMLBridgeFramework

/// A layout element positioned by its center point and size.
protocol CenterPositioned {
    var centerX: Double { get }
    var centerY: Double { get }
    var width: Double { get }
    var height: Double { get }
}

extension CenterPositioned {
    /// The element's frame as a top-left-origin `CGRect`, converting from the
    /// center-based coordinates the layout engine produces.
    var boundingRect: CGRect {
        CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

extension PositionedActivityNode: CenterPositioned {}
extension PositionedComponent: CenterPositioned {}

/// Shared Canvas drawing primitives for the native diagram renderers.
enum DiagramDrawing {
    /// Draw a centered, bold diagram title at `centerX`. No-op for an empty title.
    static func drawTitle(
        _ title: String,
        centerX: Double,
        y: Double = 18,
        color: SwiftUI.Color,
        in context: inout GraphicsContext
    ) {
        guard !title.isEmpty else { return }
        let text = Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
        context.draw(text, at: CGPoint(x: centerX, y: y), anchor: .center)
    }

    /// Fill a triangular arrowhead at `tip`, pointing along `direction`.
    static func fillArrowhead(
        at tip: CGPoint,
        direction: CGPoint,
        size: CGFloat = 8,
        color: SwiftUI.Color,
        in context: inout GraphicsContext
    ) {
        let length = max(hypot(direction.x, direction.y), 0.001)
        let unitX = direction.x / length
        let unitY = direction.y / length
        let baseX = tip.x - unitX * size
        let baseY = tip.y - unitY * size
        let perpX = -unitY
        let perpY = unitX

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: baseX + perpX * size / 2, y: baseY + perpY * size / 2))
        path.addLine(to: CGPoint(x: baseX - perpX * size / 2, y: baseY - perpY * size / 2))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}
