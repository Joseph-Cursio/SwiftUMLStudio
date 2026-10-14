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
        /// The most restrictive access level of the declaration and the declarations enclosing
        /// it, with an enclosing extension's modifier applied. `EdgeEndIds.access(of:)` also caps
        /// it by the type that extension extends.
        let ownAccess: ElementAccessibility
        /// The type the enclosing extension extends, as written there, when there is one.
        let extended: (name: String, scope: Scope)?

        init(_ entry: DiagramItem, nodeId: String?) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(entry.item)
            isExtension = entry.kind == .extension
            scope = Scope(of: entry.item)
            // Extensions are top level, so a chain holds at most one, last.
            let chain = Array(sequence(first: entry.item, next: \.parent))
            let declared = chain.prefix { $0.kind != .extension }
            var levels = declared.map { $0.accessibility.flatMap { $0 == .other ? nil : $0 } ?? .internal }
            if let enclosing = chain.first(where: { $0.kind == .extension }), !levels.isEmpty,
               let modifier = enclosing.accessibility {
                // `private extension` and `fileprivate extension` cap what they hold; `public` and
                // `package` ones set their members' default, which the parser reports as internal.
                if modifier == .private || modifier == .fileprivate {
                    levels.append(modifier)
                } else if modifier >= .package, levels[levels.count - 1] == .internal {
                    levels[levels.count - 1] = min(modifier, .public)
                }
            }
            ownAccess = levels.min() ?? .internal
            extended = chain.first { $0.kind == .extension && $0 !== entry.item }
                .flatMap { enclosing in enclosing.name.map { ($0, Scope(of: enclosing)) } }
        }
    }

    /// The node ids an `EdgeEnd` can resolve to, gathered while the nodes are built.
    struct EdgeEndIds {
        private var declaredForName: [String: [Declared]] = [:]
        private var idForDeclaration: [ObjectIdentifier: String] = [:]
        private var hiddenDeclarations: Set<ObjectIdentifier> = []

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            declaredForName[entry.name, default: []].append(Declared(entry, nodeId: nodeId))
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
        }

        /// Records a type the diagram hides. A hidden extension is simply gone: only a type can
        /// be what a name means.
        mutating func recordHidden(_ entry: DiagramItem) {
            guard entry.kind != .extension else { return }
            declaredForName[entry.name, default: []].append(Declared(entry, nodeId: nil))
            hiddenDeclarations.insert(ObjectIdentifier(entry.item))
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let name, let scope):
                guard let type = typeDeclaration(forName: name, from: scope) else {
                    return fallback(named: name, from: scope)
                }
                return node(for: type, named: name)
            case .declaration(let declaration, let name, let scope):
                if let nodeId = idForDeclaration[declaration] { return nodeId }
                if hiddenDeclarations.contains(declaration) { return standIn(for: declaration, named: name) }
                guard let type = typeDeclaration(forName: name, from: scope) else {
                    return fallback(named: name, from: scope)
                }
                return node(for: type, named: name)
            case .extended(let declaration, let name, let scope):
                // With no type of that name visible there, the extension stands for itself.
                guard let type = typeDeclaration(forName: name, from: scope) else {
                    return idForDeclaration[declaration] ?? fallback(named: name, from: scope)
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

        /// The end for a name no type visible from `scope` takes, so a type outside the diagram,
        /// such as `String`: a drawn extension of that same outside type, one whose own lookup
        /// finds no visible type of the name either, preferring one in the same file, then the
        /// same module; `nil` when there is none. An extension of a type the reference cannot
        /// see, a hidden `fileprivate` one, say, extends something else and never stands in.
        private func fallback(named name: String, from scope: Scope) -> String? {
            let extensions = (declaredForName[name] ?? []).filter { candidate in
                candidate.isExtension && candidate.nodeId != nil
                    && typeDeclaration(forName: name, from: candidate.scope) == nil
            }
            guard let first = extensions.first else { return nil }
            if let filePath = scope.filePath, let local = extensions.first(where: { $0.scope.filePath == filePath }) {
                return local.nodeId
            }
            if let module = scope.module, let sibling = extensions.first(where: { $0.scope.module == module }) {
                return sibling.nodeId
            }
            return first.nodeId
        }

        /// The type a name means where it is written, close to how Swift looks it up: among the
        /// types visible there, drawn or hidden, one declared in the same file, then in the same
        /// module, then the first in the diagram; `nil` when there is none, only extensions or
        /// nothing. A name is never matched against node ids: an undeclared `Foo_1` must not
        /// land on the node issued `Foo_1` as the second declaration of `Foo`.
        private func typeDeclaration(forName name: String, from scope: Scope, depth: Int = 0) -> Declared? {
            let types = (declaredForName[name] ?? []).filter {
                !$0.isExtension && isVisible($0, from: scope, depth: depth)
            }
            guard let first = types.first else { return nil }
            if let filePath = scope.filePath, let local = types.first(where: { $0.scope.filePath == filePath }) {
                return local
            }
            if let module = scope.module, let sibling = types.first(where: { $0.scope.module == module }) {
                return sibling
            }
            return first
        }

        /// Whether a name written in `lookup` can mean `declared`, as Swift's access control
        /// allows: a `private` or `fileprivate` type only in its own file, and a type below
        /// `package` only in its own module. A file or module that is unknown on either side is
        /// taken to be the same; parsed sources always carry a file path.
        private func isVisible(_ declared: Declared, from lookup: Scope, depth: Int) -> Bool {
            if lookup.filePath == nil || declared.scope.filePath == nil || lookup.filePath == declared.scope.filePath {
                return true
            }
            let access = access(of: declared, depth: depth)
            if access == .private || access == .fileprivate { return false }
            if let module = lookup.module, let own = declared.scope.module, module != own { return access >= .package }
            return true
        }

        /// `declared`'s access, capped by the access of the type its enclosing extension extends,
        /// as that extension's own lookup finds it. Each step resolves a shorter name, so this
        /// ends; the depth guard is a backstop.
        private func access(of declared: Declared, depth: Int) -> ElementAccessibility {
            guard let extended = declared.extended, depth < 8,
                  let type = typeDeclaration(forName: extended.name, from: extended.scope, depth: depth + 1) else {
                return declared.ownAccess
            }
            return min(declared.ownAccess, access(of: type, depth: depth + 1))
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
