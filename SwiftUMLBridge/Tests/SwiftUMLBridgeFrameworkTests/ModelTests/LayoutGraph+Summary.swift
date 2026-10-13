@testable import SwiftUMLBridgeFramework

/// What a class-diagram test compares: ids, member lines and edge ends, each in drawing order.
extension LayoutGraph {

    var nodeIds: [String] { nodes.map(\.id) }

    /// Each node's member lines, its compartments flattened.
    var memberLines: [[String]] { nodes.map { $0.compartments.flatMap(\.items) } }

    /// Each edge as `"<source id> -> <target id>"`.
    var edgeEnds: [String] { edges.map { "\($0.sourceId) -> \($0.targetId)" } }
}
