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

        return LayoutGraph(nodes: nodes, edges: edges.compactMap { $0.resolved(through: endIds) })
    }

    private struct DiagramItem {
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
        from item: SyntaxStructure, nodeId: String, kind: ElementKind, relationships: RelationshipOptions
    ) -> [PendingEdge] {
        var edges: [PendingEdge] = []
        if let inheritedTypes = item.inheritedTypes {
            // The text formats' gate, `DiagramContext.linkTarget(for:)`, matches the same names.
            // SVG read no relationship setting at all (#113, #74).
            let excluded = relationships.supertypeExcludePatterns
            for parent in inheritedTypes where parent.isExcluded(byPatterns: excluded) == false {
                guard let parentName = parent.name?.removeAngleBracketsWithContent() else { continue }
                let edgeStyle = edgeStyleForInheritance(parentName: parentName, itemKind: kind)
                let target = EdgeEnd.named(parentName, from: Scope(of: item))
                edges.append(PendingEdge(source: .node(nodeId), target: target, style: edgeStyle))
            }
        }
        if let parent = item.parent, let parentName = parent.fullName ?? parent.name {
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

// MARK: - Edge Ends

/// What `buildClassDiagram` resolves its edges through, kept apart so the builder itself
/// stays a readable size.
extension LayoutGraphBuilder {
    /// Where a declaration lives, for picking among types that share a name.
    private struct Scope {
        let filePath: String?
        let module: String?

        init(of item: SyntaxStructure) {
            filePath = item.sourceLocation?.filePath
            module = item.module
        }
    }

    /// One end of a `PendingEdge`, known by node id or — until every node exists — by what owns it.
    private enum EdgeEnd {
        case node(String)
        /// A type named `name`, as seen from a declaration in `scope`.
        case named(String, from: Scope)
        /// A particular declaration, or its name as seen from its own scope when it is not drawn.
        case declaration(ObjectIdentifier, name: String, scope: Scope)
        /// The type an extension extends, as seen from the extension's scope; the extension
        /// itself when the diagram draws no such type.
        case extended(ObjectIdentifier, name: String, scope: Scope)
    }

    /// A declaration, as `EdgeEndIds` needs it to choose among same-named types.
    private struct Declared {
        /// `nil` for a type the diagram hides: it has no node, but still takes its name's lookup.
        let nodeId: String?
        let declaration: ObjectIdentifier
        let isExtension: Bool
        let scope: Scope
        /// The most restrictive access level of the declaration and the types enclosing it.
        let access: ElementAccessibility

        /// Whether a name written in `lookup` can mean this declaration, as Swift's access
        /// control allows: a `private` or `fileprivate` type only in its own file, and a type
        /// below `package` only in its own module. Where a file or module is unknown, it is
        /// taken to be the same.
        func isVisible(from lookup: Scope) -> Bool {
            if lookup.filePath == scope.filePath { return true }
            if access == .private || access == .fileprivate { return false }
            if let module = lookup.module, let own = scope.module, module != own { return access >= .package }
            return true
        }
    }

    /// The node ids an `EdgeEnd` can resolve to, gathered while the nodes are built.
    private struct EdgeEndIds {
        private var declaredForName: [String: [Declared]] = [:]
        private var idForDeclaration: [ObjectIdentifier: String] = [:]
        private var hiddenDeclarations: Set<ObjectIdentifier> = []

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            append(entry, nodeId: nodeId)
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
        }

        /// Records a type the diagram hides. A hidden extension is simply gone: only a type can
        /// be what a name means.
        mutating func recordHidden(_ entry: DiagramItem) {
            guard entry.kind != .extension else { return }
            append(entry, nodeId: nil)
            hiddenDeclarations.insert(ObjectIdentifier(entry.item))
        }

        private mutating func append(_ entry: DiagramItem, nodeId: String?) {
            // An extension's own modifier sets its members' default access, not a cap on them.
            let enclosing = sequence(first: entry.item, next: \.parent).filter { $0.kind != .extension }
            let access = enclosing.map { level in
                level.accessibility.flatMap { $0 == .other ? nil : $0 } ?? .internal
            }.min() ?? .internal
            declaredForName[entry.name, default: []].append(Declared(
                nodeId: nodeId, declaration: ObjectIdentifier(entry.item),
                isExtension: entry.kind == .extension, scope: Scope(of: entry.item), access: access
            ))
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let name, let scope):
                guard let type = typeDeclaration(forName: name, from: scope) else { return firstDrawn(named: name) }
                return node(for: type, named: name)
            case .declaration(let declaration, let name, let scope):
                if let nodeId = idForDeclaration[declaration] { return nodeId }
                if hiddenDeclarations.contains(declaration) { return standIn(for: declaration, named: name) }
                guard let type = typeDeclaration(forName: name, from: scope) else { return firstDrawn(named: name) }
                return node(for: type, named: name)
            case .extended(let declaration, let name, let scope):
                guard let type = typeDeclaration(forName: name, from: scope) else {
                    return idForDeclaration[declaration] ?? firstDrawn(named: name)
                }
                // For a hidden type, this very extension is its stand-in: its own lookup found it.
                return type.nodeId ?? idForDeclaration[declaration] ?? standIn(for: type.declaration, named: name)
            }
        }

        /// The node an edge to `type` ends on: its own, or for a hidden type its stand-in.
        private func node(for type: Declared, named name: String) -> String? {
            type.nodeId ?? standIn(for: type.declaration, named: name)
        }

        /// A drawn extension of the hidden type `declaration`, one whose own lookup of `name`
        /// finds it, or `nil` to drop the edge. The access-level filter passes extensions, so an
        /// extension can be drawn while its type is hidden.
        private func standIn(for declaration: ObjectIdentifier, named name: String) -> String? {
            declaredForName[name]?.first { candidate in
                candidate.isExtension && candidate.nodeId != nil
                    && typeDeclaration(forName: name, from: candidate.scope)?.declaration == declaration
            }?.nodeId
        }

        /// The first drawn declaration of `name`, for a name no type in the diagram takes.
        private func firstDrawn(named name: String) -> String? {
            declaredForName[name]?.first { $0.nodeId != nil }?.nodeId
        }

        /// The type a name means where it is written, close to how Swift looks it up: among the
        /// types visible there, drawn or hidden, one declared in the same file, then in the same
        /// module, then the first in the diagram; `nil` when there is none, only extensions or
        /// nothing. A name is never matched against node ids: an undeclared `Foo_1` must not
        /// land on the node issued `Foo_1` as the second declaration of `Foo`.
        private func typeDeclaration(forName name: String, from scope: Scope) -> Declared? {
            let types = (declaredForName[name] ?? []).filter { !$0.isExtension && $0.isVisible(from: scope) }
            guard let first = types.first else { return nil }
            if let filePath = scope.filePath, let local = types.first(where: { $0.scope.filePath == filePath }) {
                return local
            }
            if let module = scope.module, let sibling = types.first(where: { $0.scope.module == module }) {
                return sibling
            }
            return first
        }
    }

    /// An edge whose ends are resolved to node ids once every node exists.
    private struct PendingEdge {
        let source: EdgeEnd
        let target: EdgeEnd
        let style: EdgeStyle

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
}
