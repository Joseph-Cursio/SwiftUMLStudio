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
        let entries = items.preparedForClassDiagram(with: configuration).compactMap { item -> DiagramItem? in
            guard let kind = item.kind, ElementKind.processable.contains(kind) else { return nil }
            guard let name = item.fullName ?? item.name else { return nil }
            return DiagramItem(item: item, kind: kind, name: name, isDrawn: item.isDrawn(in: configuration))
        }
        var nodes: [LayoutNode] = []
        var edges: [PendingEdge] = []
        var nodeIds = NodeIdAllocator(reserving: entries.filter(\.isDrawn).map(\.name))
        var endIds = EdgeEndIds()

        for entry in entries {
            // Draw the types the text formats draw, by the same `isDrawn(in:)` filter, after
            // extensions merge (#74). A hidden type gets no node, but it still decides which type
            // its name means, so an edge to it never moves to a same-named type elsewhere.
            guard entry.isDrawn else {
                endIds.recordHidden(entry)
                continue
            }
            let nodeId = nodeIds.issue(for: entry.name)
            nodes.append(buildNode(from: entry.item, nodeId: nodeId, kind: entry.kind, configuration: configuration))
            endIds.record(nodeId, for: entry)
            edges.append(contentsOf: buildEdges(
                from: entry.item, nodeId: nodeId, kind: entry.kind, relationships: configuration.relationships
            ))
        }

        return LayoutGraph(nodes: nodes, edges: resolved(edges, through: endIds))
    }

    /// `edges` between the nodes their ends name, without a carried supertype edge that repeats a
    /// supertype edge its box already draws. Repeats are found by the nodes the ends resolve to,
    /// not by name: both clauses of an `#if` name the same protocol, but two files can each declare
    /// their own `fileprivate protocol P`, and the extension in each file conforms to its own (#76).
    private static func resolved(_ edges: [PendingEdge], through endIds: EdgeEndIds) -> [LayoutEdge] {
        var supertypeEnds = Set<[String]>()
        return edges.compactMap { pending in
            guard let edge = pending.resolved(through: endIds) else { return nil }
            switch pending.role {
            case .other:
                return edge
            case .supertype:
                supertypeEnds.insert([edge.sourceId, edge.targetId])
                return edge
            case .carriedSupertype:
                return supertypeEnds.insert([edge.sourceId, edge.targetId]).inserted ? edge : nil
            }
        }
    }

    struct DiagramItem {
        let item: SyntaxStructure
        let kind: ElementKind
        let name: String
        /// Whether the diagram draws it: `SyntaxStructure.isDrawn(in:)`.
        let isDrawn: Bool
    }

    private static func buildNode(
        from item: SyntaxStructure, nodeId: String, kind: ElementKind, configuration: Configuration
    ) -> LayoutNode {
        let (properties, methods) = extractMembers(from: item, configuration: configuration)
        var compartments: [NodeCompartment] = []
        if !properties.isEmpty { compartments.append(NodeCompartment(title: nil, items: properties)) }
        if !methods.isEmpty { compartments.append(NodeCompartment(title: nil, items: methods)) }

        // An extension's bound arguments tell `extension Foo<Int>` from `extension Foo<String>` (#66).
        let boundClause = configuration.elements.showGenerics ? item.boundGenericArguments.map { "<\($0)>" } : nil
        return LayoutNode(
            id: nodeId,
            label: (item.displayName ?? item.name ?? nodeId) + (boundClause ?? ""),
            stereotype: stereotypeName(for: kind),
            compartments: compartments,
            sourceLocation: item.sourceLocation,
            module: item.module
        )
    }

    private static func buildEdges(
        from item: SyntaxStructure, nodeId: String, kind: ElementKind, relationships: RelationshipOptions
    ) -> [PendingEdge] {
        var edges: [PendingEdge] = []
        // The text formats' gate, `DiagramContext.linkTarget(for:)`, matches the same names.
        // SVG read no relationship setting at all (#113, #74).
        let excluded = relationships.supertypeExcludePatterns
        for drawn in supertypes(of: item) where drawn.supertype.isExcluded(byPatterns: excluded) == false {
            guard let parentName = drawn.supertype.name?.removeAngleBracketsWithContent() else { continue }
            let edgeStyle = edgeStyleForInheritance(parentName: parentName, itemKind: kind)
            let target = EdgeEnd.named(parentName, from: drawn.scope)
            edges.append(PendingEdge(source: .node(nodeId), target: target, style: edgeStyle, role: drawn.role))
        }
        if let parent = item.nestingParent, let parentName = parent.fullName ?? parent.name {
            // A nested type hangs off the declaration that contains it, so the second of two
            // same-named types keeps its own children; one nested in an extension hangs off the
            // type the extension extends, as seen from the extension's file — or off the
            // extension itself when the diagram draws no such type.
            let parentEnd: EdgeEnd = parent.kind == .extension
                ? .extended(ObjectIdentifier(parent), name: parentName, scope: Scope(of: parent))
                : .declaration(ObjectIdentifier(parent), name: parentName, scope: Scope(of: parent))
            edges.append(PendingEdge(source: parentEnd, target: .node(nodeId), style: .composition))
        }
        return edges
    }

    /// A supertype drawn from a type's box, and the scope its name is looked up from.
    private struct DrawnSupertype {
        let supertype: SyntaxStructure
        let scope: Scope
        let role: EdgeRole
    }

    /// The supertypes drawn from `item`'s box: its own, looked up from where it is declared, then
    /// those merged extensions carried here, looked up from where each extension is written (#76).
    /// `resolved(_:through:)` drops a carried one that ends where one before it does.
    private static func supertypes(of item: SyntaxStructure) -> [DrawnSupertype] {
        let own = (item.inheritedTypes ?? []).map {
            DrawnSupertype(supertype: $0, scope: Scope(of: item), role: .supertype)
        }
        let carried = item.carriedSupertypes.map {
            DrawnSupertype(supertype: $0.supertype, scope: $0.scope, role: .carriedSupertype)
        }
        return own + carried
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
