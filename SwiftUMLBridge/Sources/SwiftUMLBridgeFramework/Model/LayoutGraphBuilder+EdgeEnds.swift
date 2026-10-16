import Foundation

// MARK: - Edge Ends

/// What `buildClassDiagram` resolves its edges through, kept apart so the builder itself
/// stays a readable size.
extension LayoutGraphBuilder {
    /// Where a declaration lives, for picking among types that share a name.
    typealias Scope = DeclarationScope

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

    /// A declaration, as `TypeLookup` needs it to choose among same-named types.
    struct Declared {
        /// `nil` for a type the diagram hides: it has no node, but still takes its name's lookup.
        let nodeId: String?
        let declaration: ObjectIdentifier
        let isExtension: Bool
        let scope: Scope
        /// The most restrictive access level of the declaration and the declarations enclosing
        /// it, with an enclosing extension's modifier applied. `TypeLookup.access(of:)` also caps
        /// it by the type that extension extends.
        let ownAccess: ElementAccessibility
        /// The type the enclosing extension extends, as written there, when there is one.
        let extended: (name: String, scope: Scope)?

        init(_ item: SyntaxStructure, kind: ElementKind, nodeId: String?) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(item)
            isExtension = kind == .extension
            scope = Scope(of: item)
            // Extensions are top level, so a chain holds at most one, last.
            let chain = Array(sequence(first: item, next: \.parent))
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
            extended = chain.first { $0.kind == .extension && $0 !== item }
                .flatMap { enclosing in enclosing.name.map { ($0, Scope(of: enclosing)) } }
        }
    }

    /// Which declaration a type's name means where it is written. `EdgeEndIds` resolves edge
    /// ends by it, and `mergeExtensions` picks the type an extension merges into by it, so the box
    /// that shows an extension's members is the box its nested types hang off (#107).
    struct TypeLookup {
        private var declaredForName: [String: [Declared]] = [:]

        /// A lookup of every type and extension in `items`, none of them drawn.
        init(of items: [SyntaxStructure] = []) {
            for item in items {
                guard let kind = item.kind, ElementKind.processable.contains(kind),
                      let name = item.fullName ?? item.name else { continue }
                record(Declared(item, kind: kind, nodeId: nil), named: name)
            }
        }

        mutating func record(_ declared: Declared, named name: String) {
            declaredForName[name, default: []].append(declared)
        }

        /// Every declaration recorded under `name`, types and extensions, in recording order.
        func declarations(named name: String) -> [Declared] {
            declaredForName[name] ?? []
        }

        /// The type a name means where it is written, close to how Swift looks it up: the nearest
        /// (`DeclarationScope.nearest(among:scope:)`) of the types visible there, drawn or hidden;
        /// `nil` when there is none, only extensions or nothing. A name is never matched against
        /// node ids: an undeclared `Foo_1` must not land on the node issued `Foo_1` as the second
        /// declaration of `Foo`.
        func type(named name: String, from scope: Scope, depth: Int = 0) -> Declared? {
            let types = declarations(named: name).filter {
                !$0.isExtension && isVisible($0, from: scope, depth: depth)
            }
            return scope.nearest(among: types, scope: \.scope)
        }

        /// Whether a name written in `lookup` can mean `declared`, as Swift's access control
        /// allows: a `private` or `fileprivate` type only in its own file, and a type below
        /// `package` only in its own module. A file or module that is unknown on either side is
        /// taken to be the same; parsed sources always carry a file path.
        private func isVisible(_ declared: Declared, from lookup: Scope, depth: Int) -> Bool {
            if lookup.filePath == nil || declared.scope.filePath == nil || lookup.filePath == declared.scope.filePath {
                return true
            }
            var required = ElementAccessibility.internal
            if let module = lookup.module, let own = declared.scope.module, module != own { required = .package }
            // `access(of:)` only lowers `ownAccess`, so a type its own access already hides needs no
            // lookup of the type its extension extends. That lookup walks every declaration of the
            // name, and doing it for each of many same-named private types was cubic in their number.
            return declared.ownAccess >= required && access(of: declared, depth: depth) >= required
        }

        /// `declared`'s access, capped by the access of the type its enclosing extension extends,
        /// as that extension's own lookup finds it. Each step resolves a shorter name, so this
        /// ends; the depth guard is a backstop.
        private func access(of declared: Declared, depth: Int) -> ElementAccessibility {
            guard let extended = declared.extended, depth < 8,
                  let type = type(named: extended.name, from: extended.scope, depth: depth + 1) else {
                return declared.ownAccess
            }
            return min(declared.ownAccess, access(of: type, depth: depth + 1))
        }
    }

    /// The node ids an `EdgeEnd` can resolve to, gathered while the nodes are built.
    struct EdgeEndIds {
        private var lookup = TypeLookup()
        private var idForDeclaration: [ObjectIdentifier: String] = [:]
        private var hiddenDeclarations: Set<ObjectIdentifier> = []
        /// `standIn` and `fallback` for each name, worked out once: searching per edge end made a
        /// diagram of many files that each hide a same-named type cubic in their number.
        private var extensionEnds = ExtensionEnds()

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nodeId), named: entry.name)
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
            extensionEnds = ExtensionEnds()
        }

        /// Records a type the diagram hides. A hidden extension is simply gone: only a type can
        /// be what a name means.
        mutating func recordHidden(_ entry: DiagramItem) {
            guard entry.kind != .extension else { return }
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nil), named: entry.name)
            hiddenDeclarations.insert(ObjectIdentifier(entry.item))
            extensionEnds = ExtensionEnds()
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let name, let scope):
                guard let type = lookup.type(named: name, from: scope) else {
                    return fallback(named: name)
                }
                return node(for: type, named: name)
            case .declaration(let declaration, let name, let scope):
                if let nodeId = idForDeclaration[declaration] { return nodeId }
                if hiddenDeclarations.contains(declaration) { return standIn(for: declaration, named: name) }
                guard let type = lookup.type(named: name, from: scope) else {
                    return fallback(named: name)
                }
                return node(for: type, named: name)
            case .extended(let declaration, let name, let scope):
                // With no type of that name visible there, the extension stands for itself.
                guard let type = lookup.type(named: name, from: scope) else {
                    return idForDeclaration[declaration] ?? fallback(named: name)
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
            extensionEnds.ends(named: name, in: lookup).standIns[declaration]
        }

        /// The end for a name no visible type takes, so a type outside the diagram, such as
        /// `String`: the first drawn extension of that same outside type, one whose own lookup
        /// finds no visible type of the name either (#55 pins the first), or `nil` when there is
        /// none. An extension of a type the reference cannot see, a hidden `fileprivate` one,
        /// say, extends something else and never stands in.
        private func fallback(named name: String) -> String? {
            extensionEnds.ends(named: name, in: lookup).fallback
        }
    }

    /// Where the drawn extensions of one name end edges: for each type their own lookups find,
    /// the first such extension (`EdgeEndIds.standIn`), and the first that finds none
    /// (`EdgeEndIds.fallback`), each the node id of a drawn extension.
    struct NameEnds {
        var standIns: [ObjectIdentifier: String] = [:]
        var fallback: String?
    }

    /// `NameEnds` for each name, filled the first time an edge end asks for it. A class, so
    /// `EdgeEndIds.id(of:)` can fill it without being mutating; `EdgeEndIds` starts a new one
    /// whenever it records a declaration, so no entry outlives what it was worked out from.
    final class ExtensionEnds {
        private var endsForName: [String: NameEnds] = [:]

        func ends(named name: String, in lookup: TypeLookup) -> NameEnds {
            if let known = endsForName[name] { return known }
            var ends = NameEnds()
            for candidate in lookup.declarations(named: name) where candidate.isExtension {
                guard let nodeId = candidate.nodeId else { continue }
                if let type = lookup.type(named: name, from: candidate.scope) {
                    if ends.standIns[type.declaration] == nil { ends.standIns[type.declaration] = nodeId }
                } else if ends.fallback == nil {
                    ends.fallback = nodeId
                }
            }
            endsForName[name] = ends
            return ends
        }
    }

    /// What a `PendingEdge` is, for telling a merged extension's repeated conformance from the rest.
    enum EdgeRole {
        /// An edge from a type's box to a supertype its own clause names.
        case supertype
        /// An edge from a type's box to a supertype a merged extension carried to it (#76).
        case carriedSupertype
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
