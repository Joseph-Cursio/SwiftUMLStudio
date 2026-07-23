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
        let adjustedItems = prepareItems(items, configuration: configuration)
        var nodes: [LayoutNode] = []
        var edges: [LayoutEdge] = []
        var nameToId: [String: String] = [:]

        for item in adjustedItems {
            guard let kind = item.kind, ElementKind.processable.contains(kind) else { continue }
            guard let itemName = item.fullName ?? item.name else { continue }

            let nodeId = uniqueId(for: itemName, existing: &nameToId)
            nodes.append(buildNode(from: item, nodeId: nodeId, kind: kind, configuration: configuration))
            nameToId[itemName] = nodeId
            edges.append(contentsOf: buildEdges(from: item, nodeId: nodeId, kind: kind, nameToId: nameToId))
        }

        edges = resolveAndFilterEdges(edges, nameToId: nameToId, nodeIds: Set(nodes.map(\.id)))
        return LayoutGraph(nodes: nodes, edges: edges)
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

    private static func buildEdges(
        from item: SyntaxStructure, nodeId: String, kind: ElementKind, nameToId: [String: String]
    ) -> [LayoutEdge] {
        var edges: [LayoutEdge] = []
        if let inheritedTypes = item.inheritedTypes {
            for parent in inheritedTypes {
                guard let parentName = parent.name?.removeAngleBracketsWithContent() else { continue }
                let edgeStyle = edgeStyleForInheritance(parentName: parentName, itemKind: kind)
                edges.append(LayoutEdge(sourceId: nodeId, targetId: parentName, style: edgeStyle))
            }
        }
        if let parent = item.parent, let parentName = parent.fullName ?? parent.name,
           let parentId = nameToId[parentName] {
            edges.append(LayoutEdge(sourceId: parentId, targetId: nodeId, style: .composition))
        }
        return edges
    }

    private static func resolveAndFilterEdges(
        _ edges: [LayoutEdge], nameToId: [String: String], nodeIds: Set<String>
    ) -> [LayoutEdge] {
        var resolved = edges
        for idx in resolved.indices {
            if let mappedId = nameToId[resolved[idx].targetId] {
                resolved[idx] = LayoutEdge(
                    sourceId: resolved[idx].sourceId, targetId: mappedId,
                    label: resolved[idx].label, style: resolved[idx].style
                )
            }
        }
        return resolved.filter { nodeIds.contains($0.sourceId) && nodeIds.contains($0.targetId) }
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

    private static func uniqueId(for name: String, existing: inout [String: String]) -> String {
        if existing[name] == nil { return name }
        var counter = 1
        var candidate = "\(name)_\(counter)"
        while existing.values.contains(candidate) {
            counter += 1
            candidate = "\(name)_\(counter)"
        }
        return candidate
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
