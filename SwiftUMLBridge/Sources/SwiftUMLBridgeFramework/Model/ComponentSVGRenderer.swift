import Foundation

/// Computes a positioned `ComponentLayout` from a `ComponentModel` and emits
/// an SVG representation. Components are arranged in dependency-level rows:
/// "leaf" components (the ones every other target depends on) at the bottom,
/// dependent components stacked above them. Within a row, components are
/// laid out left-to-right and centered horizontally.
public enum ComponentSVGRenderer {

    // MARK: - Sizing constants
    //
    // `internal` rather than `private` so the SVG extension in
    // `ComponentSVGRenderer+SVG.swift` can read them.

    /// Estimated character width in the body font (px).
    static let charWidth: Double = 7.5
    /// Vertical space taken up by one interface line (px).
    static let interfaceLineHeight: Double = 16.0
    /// Height of the «component» header band at the top of each box (px).
    static let headerHeight: Double = 30.0
    /// Padding inside each component box (px).
    static let boxPadding: Double = 10.0
    /// Minimum box width (px) — guards against very short names.
    static let minBoxWidth: Double = 140.0
    /// Horizontal gap between adjacent component boxes (px).
    static let horizontalGap: Double = 50.0
    /// Vertical gap between dependency levels (px).
    static let verticalGap: Double = 70.0
    /// Margin around the entire diagram (px).
    static let canvasMargin: Double = 30.0

    // MARK: - Public entry point

    /// Lay out the given model and emit both a `ComponentLayout` (for native
    /// rendering) and an SVG text representation (for WebView fallback).
    public static func render(_ model: ComponentModel) -> (layout: ComponentLayout, svg: String) {
        guard !model.isEmpty else {
            return (ComponentLayout(), "")
        }
        let layout = computeLayout(model)
        let svg = renderSVG(layout)
        return (layout, svg)
    }

    /// Lay out a `ComponentModel` without producing SVG text. Exposed for
    /// testing; production callers use `render(_:)`.
    public static func computeLayout(_ model: ComponentModel) -> ComponentLayout {
        let levels = dependencyLevels(for: model)

        // Size every component first so row widths are known.
        var positioned: [String: PositionedComponent] = [:]
        for component in model.components {
            let size = boxSize(for: component)
            positioned[component.name] = PositionedComponent(
                id: component.id,
                name: component.name,
                kind: component.kind,
                providedInterfaces: component.providedInterfaces,
                width: size.width,
                height: size.height
            )
        }

        // Total canvas width = widest row.
        let rowWidths: [Double] = levels.map { row in
            guard !row.isEmpty else { return 0 }
            let boxes = row.compactMap { positioned[$0]?.width }
            return boxes.reduce(0, +) + Double(boxes.count - 1) * horizontalGap
        }
        let canvasWidth = (rowWidths.max() ?? 0) + canvasMargin * 2

        // Place each level. Row 0 is the top of the canvas; the last row is
        // the bottom, which holds the "leaf" components everyone depends on.
        var cursorY = canvasMargin
        for (rowIndex, row) in levels.enumerated() {
            let rowHeight = row
                .compactMap { positioned[$0]?.height }
                .max() ?? 0
            var cursorX = (canvasWidth - rowWidths[rowIndex]) / 2
            for name in row {
                guard var component = positioned[name] else { continue }
                component.centerX = cursorX + component.width / 2
                component.centerY = cursorY + rowHeight / 2
                positioned[name] = component
                cursorX += component.width + horizontalGap
            }
            cursorY += rowHeight + verticalGap
        }
        let canvasHeight = cursorY - verticalGap + canvasMargin

        // Preserve the original ordering from the model.
        let components = model.components.compactMap { positioned[$0.name] }
        return ComponentLayout(
            components: components,
            dependencies: model.dependencies,
            totalWidth: canvasWidth,
            totalHeight: canvasHeight
        )
    }

    // MARK: - Layering

    /// Group components into rows so each row's components depend only on
    /// components in *later* rows. Row 0 is the top of the canvas (the most
    /// "dependent" targets), the last row is the bottom (the most depended-on
    /// leaf libraries).
    static func dependencyLevels(for model: ComponentModel) -> [[String]] {
        let names = model.components.map(\.name)
        if names.isEmpty { return [] }

        // outDegree["A"] = depth of A's dependency chain.
        // Compute by traversing the `from -> to` adjacency.
        var adjacency: [String: [String]] = [:]
        for dependency in model.dependencies {
            adjacency[dependency.from, default: []].append(dependency.to)
        }

        var depthCache: [String: Int] = [:]
        let depths = names.map {
            (name: $0, depth: chainDepth(of: $0, adjacency: adjacency, cache: &depthCache))
        }
        let maxDepth = depths.map(\.depth).max() ?? 0
        var rows = Array(repeating: [String](), count: maxDepth + 1)
        for entry in depths {
            // Row 0 = highest-depth (most "consumer"-y) at the top.
            let row = maxDepth - entry.depth
            rows[row].append(entry.name)
        }
        return rows
    }

    /// How many dependencies deep `start`'s longest chain goes, with a dependency already on the
    /// walk's path counting as zero, so a cycle does not loop. Each finished target's depth goes
    /// into `cache`, which later walks read first.
    ///
    /// The walk keeps its own path instead of recursing: a target line a few hundred long
    /// overflowed the cooperative thread's stack that the CLI and Studio call this on (#149).
    private static func chainDepth(
        of start: String,
        adjacency: [String: [String]],
        cache: inout [String: Int]
    ) -> Int {
        /// A target the walk is inside, the index of its next dependency, and the deepest
        /// chain found below it so far.
        struct Step {
            let name: String
            var nextDependency = 0
            var deepest = 0
        }
        var path: [Step] = []
        var onPath = Set<String>()

        /// The depth of `name` when it is known without walking further; otherwise steps into it
        /// and returns nil.
        func enter(_ name: String) -> Int? {
            if let cached = cache[name] { return cached }
            if onPath.contains(name) { return 0 }
            if (adjacency[name] ?? []).isEmpty {
                cache[name] = 0
                return 0
            }
            path.append(Step(name: name))
            onPath.insert(name)
            return nil
        }

        if let known = enter(start) { return known }
        while let step = path.last {
            let downstream = adjacency[step.name] ?? []
            if step.nextDependency < downstream.count {
                path[path.count - 1].nextDependency += 1
                if let known = enter(downstream[step.nextDependency]) {
                    path[path.count - 1].deepest = max(step.deepest, known)
                }
                continue
            }
            path.removeLast()
            onPath.remove(step.name)
            let depth = 1 + step.deepest
            cache[step.name] = depth
            guard !path.isEmpty else { return depth }
            path[path.count - 1].deepest = max(path[path.count - 1].deepest, depth)
        }
        return 0
    }

    // MARK: - Sizing

    private static func boxSize(for component: Component) -> (width: Double, height: Double) {
        let headerString = "«\(stereotypeLabel(for: component.kind))» \(component.name)"
        var maxLabel = Double(headerString.count) * charWidth
        for interfaceName in component.providedInterfaces {
            maxLabel = max(maxLabel, Double(interfaceName.count) * charWidth)
        }
        let width = max(maxLabel + boxPadding * 2, minBoxWidth)
        let interfaceArea = component.providedInterfaces.isEmpty
            ? 0
            : Double(component.providedInterfaces.count) * interfaceLineHeight + boxPadding
        let height = headerHeight + interfaceArea + boxPadding
        return (width, height)
    }

    static func stereotypeLabel(for kind: Component.Kind) -> String {
        switch kind {
        case .executable: return "executable"
        case .library:    return "library"
        case .test:       return "test"
        case .other:      return "component"
        }
    }

    // SVG output, edge-geometry, and string helpers live in
    // `ComponentSVGRenderer+SVG.swift` to keep this file under SwiftLint's
    // type-body-length budget.
}
