import Foundation
import JavaScriptCore

/// Computes node positions and edge routes for a `LayoutGraph` using the graphre (dagre)
/// layout engine via JavaScriptCore. No WebView or internet required.
public struct DagreLayoutEngine: Sendable {

    /// Estimated character width in the diagram font (px).
    private static let charWidth: Double = 7.5
    /// Line height for members (px).
    private static let lineHeight: Double = 18.0
    /// Vertical padding inside each compartment (px).
    private static let compartmentPadding: Double = 8.0
    /// Horizontal padding inside node boxes (px).
    private static let horizontalPadding: Double = 20.0
    /// Height of the stereotype + label header area (px).
    private static let headerHeight: Double = 36.0
    /// Gap between neighbouring boxes: dagre's `nodesep` and `ranksep` (px).
    private static let nodeSpacing: Double = 60.0
    /// Space between the outermost boxes and the canvas edge: dagre's
    /// `marginx` and `marginy` (px).
    private static let canvasMargin: Double = 20.0

    /// Lay out the graph, returning a new graph with positions set.
    public static func layout(_ graph: LayoutGraph) -> LayoutGraph {
        guard !graph.nodes.isEmpty else { return graph }

        var sized = graph
        sizeNodes(&sized)

        guard let context = JSContext() else {
            BridgeLogger.shared.debug("DagreLayoutEngine: failed to create JSContext")
            return fallbackLayout(sized)
        }

        // Load graphre.js
        guard let jsURL = Bundle.module.url(forResource: "graphre", withExtension: "js"),
              let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) else {
            BridgeLogger.shared.debug("DagreLayoutEngine: graphre.js not found in bundle")
            return fallbackLayout(sized)
        }

        context.evaluateScript(jsSource)

        // Build and execute the layout script
        let layoutScript = buildLayoutScript(for: sized)
        guard let result = context.evaluateScript(layoutScript),
              !result.isUndefined else {
            BridgeLogger.shared.debug("DagreLayoutEngine: layout script returned undefined")
            return fallbackLayout(sized)
        }

        return parseResult(result, into: sized)
    }

    // MARK: - Node Sizing

    /// Estimates node dimensions based on label and compartment contents.
    private static func sizeNodes(_ graph: inout LayoutGraph) {
        for idx in graph.nodes.indices {
            let node = graph.nodes[idx]
            let labelWidth = Double(node.label.count) * charWidth + horizontalPadding
            var maxWidth = labelWidth
            var totalHeight = headerHeight

            for compartment in node.compartments where !compartment.items.isEmpty {
                totalHeight += compartmentPadding
                for item in compartment.items {
                    let itemWidth = Double(item.count) * charWidth + horizontalPadding
                    maxWidth = max(maxWidth, itemWidth)
                    totalHeight += lineHeight
                }
                totalHeight += compartmentPadding
            }

            graph.nodes[idx].width = max(maxWidth, 100)
            graph.nodes[idx].height = max(totalHeight, 50)
        }
    }

    // MARK: - JavaScript Generation

    /// Prefixes that give real nodes and module clusters separate dagre id
    /// namespaces, so the layout result can be split back into the two.
    /// Prefixing only the clusters was not enough: a node whose own id began
    /// with `cluster:` was read back as a cluster, and a node whose id was
    /// `cluster:<module>` was the same dagre node as that module's cluster.
    private static let nodeIdPrefix = "node:"
    private static let clusterIdPrefix = "cluster:"

    /// Groups node IDs by their owning module. Returns an empty map when no
    /// node carries a `module` value — the common loose-files case — so the
    /// layout falls back to a plain (non-compound) dagre graph.
    private static func moduleGroups(in graph: LayoutGraph) -> [String: [String]] {
        var groups: [String: [String]] = [:]
        for node in graph.nodes {
            guard let module = node.module else { continue }
            groups[module, default: []].append(node.id)
        }
        return groups
    }

    /// Builds a JS script that creates a dagre graph, runs layout, and returns JSON results.
    /// When the graph's nodes carry `module` values, the dagre graph is built
    /// in compound mode with one parent node per module so dagre clusters the
    /// types and reports a bounding box for each module.
    private static func buildLayoutScript(for graph: LayoutGraph) -> String {
        let modules = moduleGroups(in: graph)
        let isCompound = !modules.isEmpty
        var script = """
        (function() {
            var Graph = graphre.graphlib.Graph;
            var layout = graphre.layout;
            var graph = new Graph({ directed: true, compound: \(isCompound), multigraph: false });
            graph.setGraph({ rankdir: "TB", nodesep: \(nodeSpacing), ranksep: \(nodeSpacing),
                marginx: \(canvasMargin), marginy: \(canvasMargin) });
            graph.setDefaultEdgeLabel(function() { return {}; });

        """
        script += buildNodeStatements(for: graph)
        script += buildEdgeStatements(for: graph)
        if isCompound {
            script += buildClusterStatements(for: modules)
        }
        script += layoutAndSerialize
        return script
    }

    /// Emits `setNode` for each module's parent node and `setParent` to nest
    /// every member node beneath it. Modules are processed in sorted order so
    /// the generated script is deterministic.
    private static func buildClusterStatements(for modules: [String: [String]]) -> String {
        var result = ""
        for (module, nodeIds) in modules.sorted(by: { $0.key < $1.key }) {
            let cluster = jsStringLiteral(clusterIdPrefix + module)
            result += "    graph.setNode(\(cluster), { label: \(jsStringLiteral(module)) });\n"
            for nodeId in nodeIds {
                result += "    graph.setParent(\(jsStringLiteral(nodeIdPrefix + nodeId)), \(cluster));\n"
            }
        }
        return result
    }

    private static func buildNodeStatements(for graph: LayoutGraph) -> String {
        var result = ""
        for node in graph.nodes {
            let nodeId = jsStringLiteral(nodeIdPrefix + node.id)
            result += "    graph.setNode(\(nodeId), { width: \(node.width), height: \(node.height) });\n"
        }
        return result
    }

    private static func buildEdgeStatements(for graph: LayoutGraph) -> String {
        var result = ""
        for (idx, edge) in graph.edges.enumerated() {
            let source = jsStringLiteral(nodeIdPrefix + edge.sourceId)
            let target = jsStringLiteral(nodeIdPrefix + edge.targetId)
            result += "    graph.setEdge(\(source), \(target), { id: \"e\(idx)\" });\n"
        }
        return result
    }

    /// Renders `value` as a JavaScript string literal, quotes included, that
    /// evaluates back to exactly `value`. Node ids and module names are caller
    /// text — a module is a directory name — so they can hold `\`, `"`, or a
    /// line break, each of which changes what a hand-quoted literal means.
    /// A JSON string escapes all of those and is also a valid JS literal, but
    /// JSON leaves U+2028 and U+2029 raw, and engines before ES2019 read them
    /// as line terminators, so they are escaped here as well.
    static func jsStringLiteral(_ value: String) -> String {
        // Encoding a `String` never throws — only non-finite floats do.
        guard let data = try? JSONEncoder().encode(value),
              let json = String(bytes: data, encoding: .utf8) else { return "\"\"" }
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static let layoutAndSerialize = """

            layout(graph);
            var nodes = {};
            var clusters = {};
            graph.nodes().forEach(function(v) {
                var n = graph.node(v);
                if (!n) return;
                var box = { x: n.x, y: n.y, width: n.width, height: n.height };
                if (v.indexOf(\(jsStringLiteral(clusterIdPrefix))) === 0) {
                    box.label = n.label;
                    clusters[v] = box;
                } else {
                    nodes[v] = box;
                }
            });
            var edges = [];
            graph.edges().forEach(function(e) {
                var edge = graph.edge(e);
                if (edge && edge.points) {
                    edges.push({ source: e.v, target: e.w,
                        points: edge.points.map(function(p) { return { x: p.x, y: p.y }; }) });
                }
            });
            var graphInfo = graph.graph();
            return JSON.stringify({ nodes: nodes, edges: edges, clusters: clusters,
                width: graphInfo.width || 800, height: graphInfo.height || 600 });
        })();
        """

    // MARK: - Result Parsing

    /// Parses the JSON result from dagre back into the LayoutGraph.
    private static func parseResult(_ jsValue: JSValue, into graph: LayoutGraph) -> LayoutGraph {
        guard let jsonString = jsValue.toString(),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackLayout(graph)
        }

        var result = graph

        // Parse graph dimensions
        result.width = (json["width"] as? Double) ?? 800
        result.height = (json["height"] as? Double) ?? 600

        // Parse node positions
        if let nodesDict = json["nodes"] as? [String: [String: Double]] {
            applyNodePositions(nodesDict, to: &result)
        }

        // Parse module cluster bounding boxes (compound layout only)
        if let clustersDict = json["clusters"] as? [String: [String: Any]] {
            result.clusters = parseClusters(clustersDict)
        }

        // Parse edge points
        if let edgesArray = json["edges"] as? [[String: Any]] {
            applyEdgePoints(edgesArray, to: &result)
        }

        return result
    }

    /// Copies dagre's node positions/sizes onto the matching `LayoutNode`s.
    private static func applyNodePositions(
        _ nodesDict: [String: [String: Double]], to result: inout LayoutGraph
    ) {
        for idx in result.nodes.indices {
            guard let pos = nodesDict[nodeIdPrefix + result.nodes[idx].id] else { continue }
            result.nodes[idx].posX = pos["x"] ?? 0
            result.nodes[idx].posY = pos["y"] ?? 0
            result.nodes[idx].width = pos["width"] ?? result.nodes[idx].width
            result.nodes[idx].height = pos["height"] ?? result.nodes[idx].height
        }
    }

    /// Routes dagre's edge points onto the matching `LayoutEdge`s.
    private static func applyEdgePoints(
        _ edgesArray: [[String: Any]], to result: inout LayoutGraph
    ) {
        for edgeInfo in edgesArray {
            guard let source = edgeInfo["source"] as? String,
                  let target = edgeInfo["target"] as? String,
                  let points = edgeInfo["points"] as? [[String: Double]] else { continue }

            let layoutPoints = points.compactMap { point -> LayoutPoint? in
                guard let posX = point["x"], let posY = point["y"] else { return nil }
                return LayoutPoint(posX: posX, posY: posY)
            }

            for idx in result.edges.indices
            where nodeIdPrefix + result.edges[idx].sourceId == source
                && nodeIdPrefix + result.edges[idx].targetId == target
                && result.edges[idx].points.isEmpty {
                result.edges[idx].points = layoutPoints
                break
            }
        }
    }

    /// Converts the `clusters` JSON dictionary from a compound-graph layout
    /// into `LayoutCluster` values, sorted by module name for determinism.
    ///
    /// The prefix is stripped by scalar, as the script matched it by UTF-16
    /// unit. By `Character` it is not always eight long: a module name that
    /// starts with a combining mark, VS16, ZWJ or skin-tone modifier fuses
    /// with the `:`, and that first scalar went too.
    private static func parseClusters(_ clustersDict: [String: [String: Any]]) -> [LayoutCluster] {
        clustersDict.sorted { $0.key < $1.key }.map { clusterId, box in
            let module = String(clusterId.unicodeScalars.dropFirst(clusterIdPrefix.unicodeScalars.count))
            var cluster = LayoutCluster(id: module, label: (box["label"] as? String) ?? module)
            cluster.posX = box["x"] as? Double ?? 0
            cluster.posY = box["y"] as? Double ?? 0
            cluster.width = box["width"] as? Double ?? 0
            cluster.height = box["height"] as? Double ?? 0
            return cluster
        }
    }

    // MARK: - Fallback

    /// Grid layout for when dagre gives no result: JavaScriptCore or
    /// `graphre.js` cannot be loaded, the layout script throws or does not
    /// parse, or what it returns is not a JSON object.
    ///
    /// Every cell is the size of the largest node plus dagre's node spacing,
    /// so no two boxes overlap, and the grid sits inside dagre's margin, so
    /// every box is on the canvas. A fixed 250 × 200 cell let wide or tall
    /// nodes overlap their neighbours and run off the canvas (#61).
    static func fallbackLayout(_ graph: LayoutGraph) -> LayoutGraph {
        var result = graph
        let count = graph.nodes.count
        let columns = max(Int(ceil(sqrt(Double(count)))), 1)
        let rows = (count + columns - 1) / columns
        let cellWidth = (graph.nodes.map(\.width).max() ?? 0) + nodeSpacing
        let cellHeight = (graph.nodes.map(\.height).max() ?? 0) + nodeSpacing

        for idx in result.nodes.indices {
            let col = idx % columns
            let row = idx / columns
            result.nodes[idx].posX = canvasMargin + (Double(col) + 0.5) * cellWidth
            result.nodes[idx].posY = canvasMargin + (Double(row) + 0.5) * cellHeight
        }

        result.width = 2 * canvasMargin + Double(columns) * cellWidth
        result.height = 2 * canvasMargin + Double(rows) * cellHeight
        return result
    }
}
