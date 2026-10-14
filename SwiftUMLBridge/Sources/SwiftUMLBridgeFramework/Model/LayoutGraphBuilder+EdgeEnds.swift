import Foundation

// MARK: - Edge Ends

/// What `buildClassDiagram` resolves its edges through, kept apart so the builder itself
/// stays a readable size.
extension LayoutGraphBuilder {
    /// Where a declaration lives, for picking among types that share a name.
    struct Scope {
        let filePath: String?
        let module: String?

        init(of item: SyntaxStructure) {
            filePath = item.sourceLocation?.filePath
            module = item.module
        }
    }

    /// One end of a `PendingEdge`, known by node id or — until every node exists — by what owns it.
    enum EdgeEnd {
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
    struct Declared {
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
    struct EdgeEndIds {
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
    struct PendingEdge {
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
