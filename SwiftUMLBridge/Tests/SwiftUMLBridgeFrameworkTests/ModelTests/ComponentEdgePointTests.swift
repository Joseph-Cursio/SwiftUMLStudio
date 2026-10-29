import Testing
@testable import SwiftUMLBridgeFramework

/// `edgePoint` anchors an edge where the ray from the source's center towards the target's center
/// leaves the source box. Its doc comment used to call that the border point closest to the
/// target, which is a different point for most targets. For a target centered outside the box,
/// the two agree only when it is level with the box's center or directly above or below it, or on
/// a diagonal past a corner. No test pinned an anchor where the two rules disagree (#62).
@Suite("ComponentSVGRenderer.edgePoint")
struct ComponentEdgePointTests {

    private static let tolerance = 0.0001

    private static func box(
        centerX: Double = 0, centerY: Double = 0, width: Double = 20, height: Double = 20
    ) -> PositionedComponent {
        PositionedComponent(
            id: "box", name: "box", kind: .library,
            centerX: centerX, centerY: centerY, width: width, height: height
        )
    }

    /// Only the target's center matters, so its size is left at the default.
    private static func anchor(
        of source: PositionedComponent, towardsX targetX: Double, _ targetY: Double
    ) -> (posX: Double, posY: Double) {
        let target = box(centerX: targetX, centerY: targetY)
        let (anchorX, anchorY) = ComponentSVGRenderer.edgePoint(from: source, towards: target)
        return (anchorX, anchorY)
    }

    /// A 20×20 box at the origin. The border point nearest the target's center would be (10, 5)
    /// for the first case and (10, 10) for the second; the last two are where the two rules agree.
    @Test(
        "the anchor is where the center-to-center ray leaves a square box",
        arguments: [
            (100.0, 5.0, 10.0, 0.5),
            (100.0, 50.0, 10.0, 5.0),
            (5.0, 100.0, 0.5, 10.0),
            (-100.0, -50.0, -10.0, -5.0),
            (100.0, 0.0, 10.0, 0.0),
            (30.0, 30.0, 10.0, 10.0)
        ]
    )
    func squareBox(targetX: Double, targetY: Double, expectedX: Double, expectedY: Double) {
        let point = Self.anchor(of: Self.box(), towardsX: targetX, targetY)
        #expect(abs(point.posX - expectedX) < Self.tolerance, "x for target (\(targetX), \(targetY))")
        #expect(abs(point.posY - expectedY) < Self.tolerance, "y for target (\(targetX), \(targetY))")
    }

    /// A 140×40 box at the origin, whose diagonals have slopes of ±2/7. A steeper ray leaves
    /// through the bottom, a shallower one through the right side, and one along a diagonal at a
    /// corner.
    @Test(
        "the side the anchor is on follows the box's diagonals, not 45 degrees",
        arguments: [
            (100.0, 50.0, 40.0, 20.0),
            (100.0, 20.0, 70.0, 14.0),
            (-350.0, 100.0, -70.0, 20.0)
        ]
    )
    func wideBox(targetX: Double, targetY: Double, expectedX: Double, expectedY: Double) {
        let point = Self.anchor(of: Self.box(width: 140, height: 40), towardsX: targetX, targetY)
        #expect(abs(point.posX - expectedX) < Self.tolerance, "x for target (\(targetX), \(targetY))")
        #expect(abs(point.posY - expectedY) < Self.tolerance, "y for target (\(targetX), \(targetY))")
    }

    /// The law the doc comment states, for a box away from the origin: the anchor is on the ray
    /// towards the target, flush with one side of the box, and within its bounds on both axes.
    @Test(
        "the anchor lies on the ray towards the target and on the border",
        arguments: [
            (300.0, 7.0), (-250.0, 90.0), (13.0, -400.0), (-5.0, 380.0), (70.0, 20.0), (-1000.0, -1.0)
        ]
    )
    func onTheRayAndTheBorder(deltaX: Double, deltaY: Double) {
        let source = Self.box(centerX: 200, centerY: 100, width: 140, height: 40)
        let point = Self.anchor(of: source, towardsX: 200 + deltaX, 100 + deltaY)
        let offsetX = point.posX - 200
        let offsetY = point.posY - 100
        #expect(abs(offsetX * deltaY - offsetY * deltaX) < Self.tolerance, "off the center line")
        #expect(offsetX * deltaX + offsetY * deltaY > 0, "pointing away from the target")
        let onSide = abs(abs(offsetX) - 70) < Self.tolerance || abs(abs(offsetY) - 20) < Self.tolerance
        #expect(onSide, "not flush with a side: (\(point.posX), \(point.posY))")
        #expect(abs(offsetX) <= 70 + Self.tolerance && abs(offsetY) <= 20 + Self.tolerance)
    }

    /// The nearest-border-point rule would start this edge at (170, 70) instead.
    @Test("an edge runs between the two anchors on the center-to-center line")
    func edgeLineUsesBothAnchors() throws {
        let layout = ComponentLayout(
            components: [
                PositionedComponent(
                    id: "A", name: "A", kind: .library, centerX: 100, centerY: 50, width: 140, height: 40
                ),
                PositionedComponent(
                    id: "B", name: "B", kind: .library, centerX: 400, centerY: 200, width: 140, height: 40
                )
            ]
        )
        let line = try #require(
            ComponentSVGRenderer.edgeSVGLine(for: ComponentDependency(from: "A", to: "B"), in: layout)
        )
        #expect(line.contains(#"x1="140.0" y1="70.0" x2="360.0" y2="180.0""#), "\(line)")
    }

    @Test("coincident centers return the source's center")
    func coincidentCenters() {
        let point = Self.anchor(of: Self.box(centerX: 42, centerY: 17), towardsX: 42, 17)
        #expect(point.posX == 42)
        #expect(point.posY == 17)
    }

    /// Pins the side effect the doc comment describes. For a 140×40 box, the floor lowers the scale
    /// for a target less than 0.001 from the center in `y` and less than 0.0035 in `x`, and the
    /// anchor then lands inside the box. Both bounds are strict: the last three cases, 0.004 and
    /// exactly 0.0035 away in `x` and exactly 0.001 away in `y`, are back on the border.
    @Test(
        "the 0.001 delta floor puts the anchor inside a 140×40 box only within its reach",
        arguments: [
            (0.002, 0.0, 40.0, 0.0),
            (0.0, 0.0005, 0.0, 10.0),
            (0.004, 0.0, 70.0, 0.0),
            (0.0035, 0.0, 70.0, 0.0),
            (0.0, 0.001, 0.0, 20.0)
        ]
    )
    func deltaFloorOnAWideBox(targetX: Double, targetY: Double, expectedX: Double, expectedY: Double) {
        let point = Self.anchor(of: Self.box(width: 140, height: 40), towardsX: targetX, targetY)
        #expect(abs(point.posX - expectedX) < Self.tolerance, "x for target (\(targetX), \(targetY))")
        #expect(abs(point.posY - expectedY) < Self.tolerance, "y for target (\(targetX), \(targetY))")
    }

    /// For a 20×20 box the floor's reach is 0.001 on both axes: (0.0009, 0.0009) lands inside, and
    /// (0.0009, 0.001) on the bottom side.
    @Test(
        "for a square box the 0.001 delta floor's reach is 0.001 on both axes",
        arguments: [
            (0.0009, 0.0009, 9.0, 9.0),
            (0.0009, 0.001, 9.0, 10.0)
        ]
    )
    func deltaFloorOnASquareBox(targetX: Double, targetY: Double, expectedX: Double, expectedY: Double) {
        let point = Self.anchor(of: Self.box(), towardsX: targetX, targetY)
        #expect(abs(point.posX - expectedX) < Self.tolerance, "x for target (\(targetX), \(targetY))")
        #expect(abs(point.posY - expectedY) < Self.tolerance, "y for target (\(targetX), \(targetY))")
    }

    /// A zero half-height makes one scale 0, so the anchor never leaves the center.
    @Test(
        "a box with a zero side gets its center for every target",
        arguments: [(500.0, 7.0), (5.0, 500.0), (-300.0, -200.0)]
    )
    func zeroSidedBox(targetX: Double, targetY: Double) {
        let point = Self.anchor(of: Self.box(centerX: 5, centerY: 7, width: 140, height: 0), towardsX: targetX, targetY)
        #expect(point.posX == 5)
        #expect(point.posY == 7)
    }
}
