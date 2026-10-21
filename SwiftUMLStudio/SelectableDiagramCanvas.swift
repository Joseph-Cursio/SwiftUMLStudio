import SwiftUI

/// A native canvas whose nodes can be selected by tap or arrow key and highlighted on hover:
/// `NativeDiagramView` and `NativeSequenceDiagramView`. Each supplies only its geometry — which
/// node sits at a point, and which comes next in a direction — and gets the handlers and the
/// interaction modifiers from here, which the two used to carry a copy of each (#209).
///
/// The handlers are internal rather than inlined in the modifier so they are unit-testable:
/// `ImageRenderer` drives the drawing code but never fires gestures or key presses, and
/// ViewInspector cannot reach these views at all (GeometryReader trap — see
/// NativeDiagramViewTests.swift).
protocol SelectableDiagramCanvas {
    var viewport: DiagramViewport { get }

    /// The id of the node under `location`, in the canvas's own coordinate space.
    func nodeID(at location: CGPoint) -> String?

    /// The id of the node an arrow key in `direction` moves to from `currentID`, or `nil` when
    /// there is none that way.
    func nodeID(after currentID: String, direction: NativeDiagramGeometry.NavigationDirection) -> String?

    /// The id of the node an arrow key selects when nothing is selected.
    func firstNodeID() -> String?
}

extension SelectableDiagramCanvas {
    /// Selects whichever node sits under `location`, or clears the selection when the tap lands
    /// on empty canvas.
    func select(at location: CGPoint) {
        viewport.selectedNodeId = nodeID(at: location)
    }

    func updateHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            viewport.hoveredNodeId = nodeID(at: location)
        case .ended:
            viewport.hoveredNodeId = nil
        }
    }

    func clearSelection() -> KeyPress.Result {
        viewport.selectedNodeId = nil
        return .handled
    }

    /// Moves the selection to the next node in `direction`, or selects the first node when
    /// nothing is selected or nothing lies that way.
    func handleArrow(_ direction: NativeDiagramGeometry.NavigationDirection) -> KeyPress.Result {
        if let currentID = viewport.selectedNodeId,
           let next = nodeID(after: currentID, direction: direction) {
            viewport.selectedNodeId = next
            return .handled
        }
        if let first = firstNodeID() {
            viewport.selectedNodeId = first
            return .handled
        }
        return .ignored
    }
}

/// The interaction modifiers shared by the selectable canvases, in the order they were applied
/// inline: the named coordinate space first, so taps and hover read the unscaled canvas, then
/// pan/zoom, tap-to-select, double-tap reset, hover, focus, the arrow keys and Escape.
private struct SelectableCanvasInteraction<Canvas: SelectableDiagramCanvas>: ViewModifier {
    let canvas: Canvas
    let coordinateSpace: String
    let arrows: [NativeDiagramGeometry.NavigationDirection]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: coordinateSpace)
            .canvasPanZoom(viewport: canvas.viewport)
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(coordinateSpace))
                    .onEnded { canvas.select(at: $0.location) }
            )
            .onTapGesture(count: 2) { canvas.viewport.reset() }
            .onContinuousHover(coordinateSpace: .named(coordinateSpace)) { canvas.updateHover($0) }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: Set(arrows.map(\.key))) { press in
                guard let direction = arrows.first(where: { $0.key == press.key }) else { return .ignored }
                return canvas.handleArrow(direction)
            }
            .onKeyPress(.escape) { canvas.clearSelection() }
    }
}

extension NativeDiagramGeometry.NavigationDirection {
    /// The arrow key that moves the selection this way. `nonisolated` because it is a lookup on
    /// an enum case, which needs no main actor.
    nonisolated var key: KeyEquivalent {
        switch self {
        case .upward: return .upArrow
        case .down: return .downArrow
        case .left: return .leftArrow
        case .right: return .rightArrow
        }
    }
}

extension View {
    /// Apply the selection, hover, keyboard and pan/zoom interaction of `canvas`, reading taps
    /// and hover in the coordinate space named `coordinateSpace`. Only the `arrows` keys move
    /// the selection.
    func selectableCanvasInteraction(
        _ canvas: some SelectableDiagramCanvas,
        coordinateSpace: String,
        arrows: [NativeDiagramGeometry.NavigationDirection]
    ) -> some View {
        modifier(SelectableCanvasInteraction(canvas: canvas, coordinateSpace: coordinateSpace, arrows: arrows))
    }
}
