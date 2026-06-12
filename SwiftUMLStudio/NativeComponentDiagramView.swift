import SwiftUI
import SwiftUMLBridgeFramework

/// Native SwiftUI Canvas renderer for component diagrams.
/// Reads from a positioned `ComponentLayout` with pan and zoom support.
struct NativeComponentDiagramView: View {
    let layout: ComponentLayout
    let viewport: DiagramViewport

    // MARK: - Colors

    /// Body strokes + edge arrows — adapts to system label color.
    private static let strokeColor = SwiftUI.Color(nsColor: .labelColor).opacity(0.7)
    /// Component box fill — slightly tinted off the canvas bg for separation.
    private static let boxFill = SwiftUI.Color(nsColor: .controlBackgroundColor)
    /// Header band fill — a more saturated tint so the «stereotype» row stands out.
    private static let headerFill = SwiftUI.Color(nsColor: .controlColor)
    /// Body / header text colors.
    private static let titleColor = SwiftUI.Color(nsColor: .labelColor)
    private static let stereotypeColor = SwiftUI.Color(nsColor: .secondaryLabelColor)
    private static let interfaceColor = SwiftUI.Color(nsColor: .labelColor)

    /// Geometry constants. Must stay in sync with `ComponentSVGRenderer`'s
    /// header/box padding so the rendered native canvas matches the layout's
    /// reported sizes.
    private static let headerHeight: Double = 30
    private static let boxPadding: Double = 10
    private static let interfaceLineHeight: Double = 16
    private static let cornerRadius: Double = 4

    var body: some View {
        GeometryReader { geometry in
            let canvasWidth = max(layout.totalWidth, Double(geometry.size.width))
            let canvasHeight = max(layout.totalHeight, Double(geometry.size.height))

            Canvas { context, _ in
                drawEdges(in: &context)
                drawComponents(in: &context)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .canvasPanZoom(viewport: viewport)
            .onTapGesture(count: 2) { viewport.reset() }
            .diagramCanvasChrome(
                viewport: viewport,
                contentSize: CGSize(width: layout.totalWidth, height: layout.totalHeight),
                visibleSize: geometry.size,
                label: "Component diagram canvas",
                identifier: "nativeComponentCanvas"
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Drawing

    private func drawComponents(in context: inout GraphicsContext) {
        for component in layout.components {
            drawBox(component: component, in: &context)
        }
    }

    private func drawBox(component: PositionedComponent, in context: inout GraphicsContext) {
        let originX = component.centerX - component.width / 2
        let originY = component.centerY - component.height / 2
        let boxRect = CGRect(x: originX, y: originY, width: component.width, height: component.height)
        let headerRect = CGRect(x: originX, y: originY, width: component.width, height: Self.headerHeight)

        let boxPath = Path(roundedRect: boxRect, cornerRadius: Self.cornerRadius)
        context.fill(boxPath, with: .color(Self.boxFill))
        context.stroke(boxPath, with: .color(Self.strokeColor), lineWidth: 1.2)

        let headerPath = Path(roundedRect: headerRect, cornerRadius: Self.cornerRadius)
        context.fill(headerPath, with: .color(Self.headerFill))
        context.stroke(headerPath, with: .color(Self.strokeColor), lineWidth: 1.2)

        let stereotypeText = Text("«\(stereotypeLabel(for: component.kind))»")
            .font(.system(size: 10).italic())
            .foregroundStyle(Self.stereotypeColor)
        context.draw(
            stereotypeText,
            at: CGPoint(x: component.centerX, y: originY + 11),
            anchor: .center
        )

        let titleText = Text(component.name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Self.titleColor)
        context.draw(
            titleText,
            at: CGPoint(x: component.centerX, y: originY + 23),
            anchor: .center
        )

        var interfaceY = originY + Self.headerHeight + Self.boxPadding
        for interfaceName in component.providedInterfaces {
            let text = Text(interfaceName)
                .font(.system(size: 11))
                .foregroundStyle(Self.interfaceColor)
            context.draw(
                text,
                at: CGPoint(x: originX + Self.boxPadding, y: interfaceY + 7),
                anchor: .leading
            )
            interfaceY += Self.interfaceLineHeight
        }
    }

    private func drawEdges(in context: inout GraphicsContext) {
        for dependency in layout.dependencies {
            guard
                let source = layout.component(named: dependency.from),
                let target = layout.component(named: dependency.to)
            else { continue }
            let start = edgePoint(from: source, towards: target)
            let end = edgePoint(from: target, towards: source)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(Self.strokeColor),
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            )
            drawArrowHead(at: end, from: start, in: &context)
        }
    }

    private func drawArrowHead(at point: CGPoint, from origin: CGPoint, in context: inout GraphicsContext) {
        let deltaX = point.x - origin.x
        let deltaY = point.y - origin.y
        let length = max(hypot(deltaX, deltaY), 0.001)
        let unitX = deltaX / length
        let unitY = deltaY / length
        let arrowLength: CGFloat = 8
        let baseX = point.x - unitX * arrowLength
        let baseY = point.y - unitY * arrowLength
        let perpX = -unitY
        let perpY = unitX

        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(x: baseX + perpX * arrowLength / 2, y: baseY + perpY * arrowLength / 2))
        path.addLine(to: CGPoint(x: baseX - perpX * arrowLength / 2, y: baseY - perpY * arrowLength / 2))
        path.closeSubpath()
        context.fill(path, with: .color(Self.strokeColor))
    }

    /// Project to whichever rectangle border of `source` lies nearest the
    /// line towards `target`. Mirrors `ComponentSVGRenderer.edgePoint`.
    private func edgePoint(
        from source: PositionedComponent,
        towards target: PositionedComponent
    ) -> CGPoint {
        let deltaX = target.centerX - source.centerX
        let deltaY = target.centerY - source.centerY
        if deltaX == 0, deltaY == 0 {
            return CGPoint(x: source.centerX, y: source.centerY)
        }
        let halfW = source.width / 2
        let halfH = source.height / 2
        let scaleX = halfW / max(abs(deltaX), 0.001)
        let scaleY = halfH / max(abs(deltaY), 0.001)
        let scale = min(scaleX, scaleY)
        return CGPoint(
            x: source.centerX + deltaX * scale,
            y: source.centerY + deltaY * scale
        )
    }

    private func stereotypeLabel(for kind: Component.Kind) -> String {
        switch kind {
        case .executable: return "executable"
        case .library:    return "library"
        case .test:       return "test"
        case .other:      return "component"
        }
    }
}
