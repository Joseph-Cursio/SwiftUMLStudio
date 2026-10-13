@testable import SwiftUMLBridgeFramework

extension LayoutGraph {

    /// Ids of the nodes whose box is not wholly inside the `width` × `height` canvas (#60).
    ///
    /// A dagre layout keeps every box inside its canvas. A node dagre never placed stays at
    /// (0, 0), three quarters off the canvas, and the grid fallback ignores node size, so a wide
    /// box there runs off the edge. A width check cannot tell these apart: `sizeNodes` sets every
    /// width before the script runs, and both paths keep it.
    var nodesOutsideCanvas: [String] {
        nodes.filter { node in
            node.posX - node.width / 2 < 0 || node.posY - node.height / 2 < 0
                || node.posX + node.width / 2 > width || node.posY + node.height / 2 > height
        }.map(\.id)
    }
}
