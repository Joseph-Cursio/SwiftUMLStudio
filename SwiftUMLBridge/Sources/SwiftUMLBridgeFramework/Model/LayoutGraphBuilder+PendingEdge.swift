import Foundation

// MARK: - Pending Edges

/// The edges `buildClassDiagram` collects before every node exists, and the node ids it hands
/// out, kept apart so the builder itself stays a readable size.
extension LayoutGraphBuilder {
    /// What a `PendingEdge` is, for telling a merged extension's repeated conformance from the rest.
    enum EdgeRole {
        /// An edge from a type's box to a supertype its own clause names.
        case supertype
        /// An edge from a type's box to a supertype a merged extension carried to it (#76).
        case carriedSupertype
        /// An edge from an extension's box to the type it extends, kept only when that end is a
        /// drawn type, not the extension standing in for itself (#75).
        case extendedType
        case other
    }

    /// An edge whose ends are resolved to node ids once every node exists.
    struct PendingEdge {
        let source: EdgeEnd
        let target: EdgeEnd
        let style: EdgeStyle
        var role: EdgeRole = .other

        /// The edge between the nodes its ends name, or `nil` when an end names an element the
        /// diagram does not draw.
        func resolved(through endIds: EdgeEndIds) -> LayoutEdge? {
            guard let sourceId = endIds.id(of: source), let targetId = endIds.id(of: target) else { return nil }
            return LayoutEdge(sourceId: sourceId, targetId: targetId, style: style)
        }
    }

    /// Hands out node ids that are distinct within one diagram. The dagre layout keys nodes by
    /// id, so two nodes sharing one are placed, sized and drawn as one.
    ///
    /// Every drawn element's name is reserved up front, so the first declaration of a name keeps
    /// it and a later one's `_n` suffix never takes a name declared further on.
    struct NodeIdAllocator {
        private var taken: Set<String>
        private var issuedNames: Set<String> = []

        init(reserving names: [String]) {
            taken = Set(names)
        }

        mutating func issue(for name: String) -> String {
            var nodeId = name
            if issuedNames.contains(name) {
                var counter = 1
                repeat {
                    nodeId = "\(name)_\(counter)"
                    counter += 1
                } while taken.contains(nodeId)
            }
            issuedNames.insert(name)
            taken.insert(nodeId)
            return nodeId
        }
    }
}
