import CoreGraphics
import SwiftUI
import SwiftUMLBridgeFramework

/// Pure geometry helpers for `NativeDiagramView` — separated from the Canvas
/// draw calls so the math is unit-testable.
nonisolated enum NativeDiagramGeometry {

    // MARK: - Layout constants

    static let headerHeight: CGFloat = 36
    static let lineHeight: CGFloat = 18
    static let padding: CGFloat = 10
    static let cornerRadius: CGFloat = 4
    static let arrowLength: CGFloat = 12
    static let arrowWidth: CGFloat = 6

    // MARK: - Colors

    static let headerColors: [String: SwiftUI.Color] = [
        "class": SwiftUI.Color(red: 0.29, green: 0.56, blue: 0.85),
        "struct": SwiftUI.Color(red: 0.48, green: 0.41, blue: 0.93),
        "enum": SwiftUI.Color(red: 0.91, green: 0.66, blue: 0.22),
        "protocol": SwiftUI.Color(red: 0.31, green: 0.78, blue: 0.47),
        "actor": SwiftUI.Color(red: 0.88, green: 0.40, blue: 0.40),
        "extension": SwiftUI.Color.gray,
        "macro": SwiftUI.Color(red: 0.80, green: 0.40, blue: 0.80),
        "warning": SwiftUI.Color(red: 1.0, green: 0.8, blue: 0.8)
    ]

    /// Returns the header color for a given stereotype, falling back to `class`
    /// when the stereotype is unknown.
    static func headerColor(for stereotype: String?) -> SwiftUI.Color {
        let key = stereotype ?? "class"
        return headerColors[key] ?? headerColors["class"] ?? SwiftUI.Color.gray
    }

    /// Deterministic color for a module name — hashes the name into a hue so
    /// the same module gets the same swatch on every render. Used by the
    /// native canvas to draw a thin colored stripe along the bottom of each
    /// node when it carries a `module` value.
    static func moduleColor(for module: String) -> SwiftUI.Color {
        let hash = module.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(hash % 360) / 360.0
        return SwiftUI.Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    // MARK: - Node geometry

    /// Bounding rectangle of a laid-out node in canvas coordinates.
    static func nodeRect(for node: LayoutNode) -> CGRect {
        CGRect(
            x: node.posX - node.width / 2,
            y: node.posY - node.height / 2,
            width: node.width,
            height: node.height
        )
    }

    /// Bounding rectangle of a laid-out module cluster in canvas coordinates.
    static func clusterRect(for cluster: LayoutCluster) -> CGRect {
        CGRect(
            x: cluster.posX - cluster.width / 2,
            y: cluster.posY - cluster.height / 2,
            width: cluster.width,
            height: cluster.height
        )
    }

    /// Returns the topmost node whose bounds contain `point`, or `nil` if none.
    /// Iterates in reverse so later-drawn nodes win when bounds overlap.
    static func hitNode(in graph: LayoutGraph, at point: CGPoint) -> LayoutNode? {
        graph.nodes.reversed().first { nodeRect(for: $0).contains(point) }
    }

    // MARK: - Arrow-key navigation

    enum NavigationDirection: Sendable {
        case up, down, left, right
    }

    /// The leftmost-topmost node in the graph. Used as the starting selection
    /// when the user presses an arrow key with nothing selected.
    static func firstNode(in graph: LayoutGraph) -> LayoutNode? {
        graph.nodes.min { lhs, rhs in
            (lhs.posY, lhs.posX) < (rhs.posY, rhs.posX)
        }
    }

    /// The spatially-nearest node in `direction` from `currentId`, or `nil`
    /// when no candidate exists. A candidate counts as "in" the direction when
    /// its center is strictly past the current node's center along the
    /// direction axis AND the dominant axis matches the direction (so a
    /// node directly below doesn't count as a "right" candidate).
    static func nextNode(
        in graph: LayoutGraph,
        from currentId: String,
        direction: NavigationDirection
    ) -> LayoutNode? {
        guard let current = graph.nodes.first(where: { $0.id == currentId }) else { return nil }
        let candidates = graph.nodes.filter { node in
            node.id != currentId && isInDirection(direction, from: current, to: node)
        }
        return candidates.min { distanceSquared($0, current) < distanceSquared($1, current) }
    }

    private static func isInDirection(
        _ direction: NavigationDirection, from origin: LayoutNode, to candidate: LayoutNode
    ) -> Bool {
        let dx = candidate.posX - origin.posX
        let dy = candidate.posY - origin.posY
        switch direction {
        case .right: return dx > 0 && abs(dx) >= abs(dy)
        case .left:  return dx < 0 && abs(dx) >= abs(dy)
        case .down:  return dy > 0 && abs(dy) > abs(dx)
        case .up:    return dy < 0 && abs(dy) > abs(dx)
        }
    }

    private static func distanceSquared(_ lhs: LayoutNode, _ rhs: LayoutNode) -> Double {
        let dx = lhs.posX - rhs.posX
        let dy = lhs.posY - rhs.posY
        return dx * dx + dy * dy
    }

    /// Header-band rectangle (top strip of the node) clamped to the node height.
    static func headerRect(for node: LayoutNode) -> CGRect {
        let rect = nodeRect(for: node)
        let headerH = min(headerHeight, node.height)
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerH)
    }

    // MARK: - Edge styling

    /// Stroke style for an edge — dashed for realization/dependency, solid otherwise.
    static func strokeStyle(for edgeStyle: EdgeStyle) -> StrokeStyle {
        switch edgeStyle {
        case .realization, .dependency:
            return StrokeStyle(lineWidth: 1.2, dash: [6, 3])
        case .inheritance, .composition, .association:
            return StrokeStyle(lineWidth: 1.2)
        }
    }

    // MARK: - Arrowhead math

    struct ArrowheadPoints: Equatable {
        let left: CGPoint
        let right: CGPoint
    }

    /// Compute the two base points of a triangular arrowhead pointing from
    /// `prev` toward `tip`.
    static func arrowheadPoints(tip: CGPoint, prev: CGPoint) -> ArrowheadPoints {
        let angle = atan2(tip.y - prev.y, tip.x - prev.x)
        let leftAngle = angle + .pi - .pi / 6
        let rightAngle = angle + .pi + .pi / 6
        return ArrowheadPoints(
            left: CGPoint(
                x: tip.x + arrowLength * cos(leftAngle),
                y: tip.y + arrowLength * sin(leftAngle)
            ),
            right: CGPoint(
                x: tip.x + arrowLength * cos(rightAngle),
                y: tip.y + arrowLength * sin(rightAngle)
            )
        )
    }

    // MARK: - Diamond math (composition arrow)

    struct DiamondPoints: Equatable {
        let tip: CGPoint
        let mid: CGPoint
        let far: CGPoint
        let left: CGPoint
        let right: CGPoint
    }

    /// Compute the four vertices of a composition-style diamond given the tip
    /// and direction of the edge.
    static func diamondPoints(
        tip: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat
    ) -> DiamondPoints {
        let back = angle + .pi
        let mid = CGPoint(
            x: tip.x + length * cos(back),
            y: tip.y + length * sin(back)
        )
        let far = CGPoint(
            x: tip.x + length * 2 * cos(back),
            y: tip.y + length * 2 * sin(back)
        )
        let leftAngle = angle + .pi / 2
        let rightAngle = angle - .pi / 2
        return DiamondPoints(
            tip: tip,
            mid: mid,
            far: far,
            left: CGPoint(
                x: mid.x + width * cos(leftAngle),
                y: mid.y + width * sin(leftAngle)
            ),
            right: CGPoint(
                x: mid.x + width * cos(rightAngle),
                y: mid.y + width * sin(rightAngle)
            )
        )
    }
}
