import Foundation

/// Builds a `LayoutGraph` from parsed `SyntaxStructure` items for class diagrams,
/// or from a `DependencyGraphModel` for dependency graphs.
struct LayoutGraphBuilder {

    // MARK: - Class Diagram

    /// Build a layout graph from parsed syntax structures (class diagram).
    static func buildClassDiagram(
        from items: [SyntaxStructure],
        configuration: Configuration
    ) -> LayoutGraph {
        let drawn = prepareItems(items, configuration: configuration).compactMap { item -> DrawnItem? in
            guard let kind = item.kind, ElementKind.processable.contains(kind) else { return nil }
            guard let name = item.fullName ?? item.name else { return nil }
            return DrawnItem(item: item, kind: kind, name: name)
        }
        var nodes: [LayoutNode] = []
        var edges: [PendingEdge] = []
        var nodeIds = NodeIdAllocator(reserving: drawn.map(\.name))
        // Edges name their ends; a name resolves to its first declaration — the type itself,
        // since types sort before their extensions.
        var firstIdForName: [String: String] = [:]

        for entry in drawn {
            let nodeId = nodeIds.issue(for: entry.name)
            nodes.append(buildNode(from: entry.item, nodeId: nodeId, kind: entry.kind, configuration: configuration))
            if firstIdForName[entry.name] == nil {
                firstIdForName[entry.name] = nodeId
            }
            edges.append(contentsOf: buildEdges(from: entry.item, nodeId: nodeId, kind: entry.kind))
        }

        return LayoutGraph(nodes: nodes, edges: edges.compactMap { $0.resolved(through: firstIdForName) })
    }

    private struct DrawnItem {
        let item: SyntaxStructure
        let kind: ElementKind
        let name: String
    }

    /// One end of a `PendingEdge`: a node id, or the name of the element that should own the end.
    private enum EdgeEnd {
        case node(String)
        case named(String)
    }

    /// An edge whose ends are known by node id or, until every node exists, by element name.
    private struct PendingEdge {
        let source: EdgeEnd
        let target: EdgeEnd
        let style: EdgeStyle

        /// The edge between the nodes its ends name, or `nil` when an end names an element the
        /// diagram does not draw. A name is never matched against node ids: an undeclared
        /// `Foo_1` must not land on the node issued `Foo_1` as the second declaration of `Foo`.
        func resolved(through firstIdForName: [String: String]) -> LayoutEdge? {
            guard let sourceId = id(of: source, firstIdForName), let targetId = id(of: target, firstIdForName)
            else { return nil }
            return LayoutEdge(sourceId: sourceId, targetId: targetId, style: style)
        }

        private func id(of end: EdgeEnd, _ firstIdForName: [String: String]) -> String? {
            switch end {
            case .node(let nodeId): return nodeId
            case .named(let name): return firstIdForName[name]
            }
        }
    }

    /// Hands out node ids that are distinct within one diagram. The dagre layout keys nodes by
    /// id, so two nodes sharing one are placed, sized and drawn as one.
    ///
    /// Every drawn element's name is reserved up front, so the first declaration of a name keeps
    /// it and a later one's `_n` suffix never takes a name declared further on.
    private struct NodeIdAllocator {
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

    private static func prepareItems(_ items: [SyntaxStructure], configuration: Configuration) -> [SyntaxStructure] {
        var adjusted = items
        if configuration.elements.showNestedTypes {
            adjusted = adjusted.populateNestedTypes()
        }
        adjusted = adjusted.orderedByProtocolsFirstExtensionsLast()
        if configuration.shallExtensionsBeMerged {
            adjusted = adjusted.mergeExtensions(
                mergedMemberIndicator: configuration.elements.mergedExtensionMemberIndicator
            )
        }
        return adjusted
    }

    private static func buildNode(
        from item: SyntaxStructure, nodeId: String, kind: ElementKind, configuration: Configuration
    ) -> LayoutNode {
        let (properties, methods) = extractMembers(from: item, configuration: configuration)
        var compartments: [NodeCompartment] = []
        if !properties.isEmpty { compartments.append(NodeCompartment(title: nil, items: properties)) }
        if !methods.isEmpty { compartments.append(NodeCompartment(title: nil, items: methods)) }

        return LayoutNode(
            id: nodeId,
            label: item.displayName ?? item.name ?? nodeId,
            stereotype: stereotypeName(for: kind),
            compartments: compartments,
            sourceLocation: item.sourceLocation,
            module: item.module
        )
    }

    private static func buildEdges(from item: SyntaxStructure, nodeId: String, kind: ElementKind) -> [PendingEdge] {
        var edges: [PendingEdge] = []
        if let inheritedTypes = item.inheritedTypes {
            for parent in inheritedTypes {
                guard let parentName = parent.name?.removeAngleBracketsWithContent() else { continue }
                let edgeStyle = edgeStyleForInheritance(parentName: parentName, itemKind: kind)
                edges.append(PendingEdge(source: .node(nodeId), target: .named(parentName), style: edgeStyle))
            }
        }
        if let parent = item.parent, let parentName = parent.fullName ?? parent.name {
            edges.append(PendingEdge(source: .named(parentName), target: .node(nodeId), style: .composition))
        }
        return edges
    }

    // MARK: - Dependency Graph

    /// Build a layout graph from a dependency graph model.
    static func buildDependencyGraph(from model: DependencyGraphModel) -> LayoutGraph {
        var nodeNames = Set<String>()
        for edge in model.edges {
            nodeNames.insert(edge.from)
            nodeNames.insert(edge.to)
        }

        let cycleNodes = model.detectCycles()
        let nodes = nodeNames.sorted().map { name in
            LayoutNode(id: name, label: name,
                       stereotype: cycleNodes.contains(name) ? "warning" : nil)
        }

        let edges = model.edges.map { edge in
            let style: EdgeStyle
            switch edge.kind {
            case .inherits: style = .inheritance
            case .conforms: style = .realization
            case .imports: style = .dependency
            }
            return LayoutEdge(sourceId: edge.from, targetId: edge.to, style: style)
        }

        return LayoutGraph(nodes: nodes, edges: edges)
    }

    // MARK: - Helpers

    private static func stereotypeName(for kind: ElementKind) -> String {
        switch kind {
        case .class: return "class"
        case .struct: return "struct"
        case .enum: return "enum"
        case .protocol: return "protocol"
        case .actor: return "actor"
        case .extension: return "extension"
        case .macro: return "macro"
        default: return "class"
        }
    }

    private static func edgeStyleForInheritance(parentName: String, itemKind: ElementKind) -> EdgeStyle {
        itemKind == .extension ? .dependency : .inheritance
    }

    private static func extractMembers(
        from item: SyntaxStructure, configuration: Configuration
    ) -> (properties: [String], methods: [String]) {
        var properties: [String] = []
        var methods: [String] = []
        guard let substructure = item.substructure, !substructure.isEmpty else {
            return (properties, methods)
        }

        let showAccess = configuration.elements.showMemberAccessLevelAttribute
        let accessLevels: [ElementAccessibility] = configuration.elements
            .showMembersWithAccessLevel.compactMap { ElementAccessibility(orig: $0) }

        for sub in substructure {
            let actual = sub.kind == .enumcase ? sub.substructure?.first : sub
            guard let element = actual else { continue }

            if item.kind != .extension {
                let effective = element.accessibility ?? .internal
                if !accessLevels.contains(effective) { continue }
            }

            let prefix = showAccess ? accessPrefix(for: element) : ""
            classifyMember(element, prefix: prefix, properties: &properties, methods: &methods)
        }
        return (properties, methods)
    }

    private static func classifyMember(
        _ element: SyntaxStructure, prefix: String,
        properties: inout [String], methods: inout [String]
    ) {
        guard let kind = element.kind, let memberName = element.name else { return }
        switch kind {
        case .functionMethodInstance:
            methods.append("\(prefix)\(memberName)()")
        case .functionMethodStatic:
            methods.append("\(prefix)static \(memberName)()")
        case .varInstance:
            properties.append("\(prefix)\(memberName)\(element.typename.map { ": \($0)" } ?? "")")
        case .varStatic:
            properties.append("\(prefix)static \(memberName)\(element.typename.map { ": \($0)" } ?? "")")
        case .enumelement:
            properties.append(memberName)
        default:
            break
        }
    }

    private static func accessPrefix(for element: SyntaxStructure) -> String {
        guard let accessibility = element.accessibility else { return "~ " }
        switch accessibility {
        case .open, .public: return "+ "
        case .internal, .package, .other: return "~ "
        case .private, .fileprivate: return "- "
        }
    }
}
