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
        /// A type written as `name` in the inheritance clause of a declaration in `scope`, which
        /// may name a member of a type around it (`TypeLookup.qualifiedName(ofWritten:from:)`).
        case named(String, from: Scope)
        /// A particular declaration, or its name as seen from its own scope when it is not drawn.
        case declaration(ObjectIdentifier, name: String, scope: Scope)
        /// The type an extension extends, as seen from the extension's scope; the extension
        /// itself when the diagram draws no such type.
        case extended(ObjectIdentifier, name: String, scope: Scope)
    }

    /// A declaration, as `TypeLookup` needs it to choose among same-named types. A class, since
    /// every lookup filters and passes them along: a copy of the struct it was retained each of
    /// its strings, its two scopes and their imports.
    final class Declared: Sendable {
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
        /// For a typealias, the name of the type it aliases, looked up from its own scope (#125).
        let aliasTarget: String?
        /// The module of the outermost type around the declaration, before any extension: its
        /// container's for a member `mergeExtensions` moved into a type of another module.
        let outermostModule: String?

        /// `container` is the declaration `item` is a member of, when `item.parent` is not set:
        /// a typealias is never flattened out of its type's members.
        init(_ item: SyntaxStructure, kind: ElementKind, nodeId: String?, in container: SyntaxStructure? = nil) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(item)
            isExtension = kind == .extension
            aliasTarget = kind == .typealias ? item.typename : nil
            scope = Scope(of: item, in: container)
            // Extensions are top level, so a chain holds at most one, last.
            let chain = Array(sequence(first: item) { $0 === item ? container ?? $0.parent : $0.parent })
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
            outermostModule = declared.last?.module ?? scope.module
            extended = chain.first { $0.kind == .extension && $0 !== item }
                .flatMap { enclosing in enclosing.name.map { ($0, Scope(of: enclosing)) } }
        }
    }

    /// A declaration as `TypeLookup` recorded it: the name it is recorded under, and its place
    /// in recording order.
    struct RecordedDeclaration {
        let name: String
        let order: Int
        let declared: Declared
    }

    /// Which declaration a type's name means where it is written. `EdgeEndIds` resolves edge
    /// ends by it, and `mergeExtensions` picks the type an extension merges into by it, so the box
    /// that shows an extension's members is the box its nested types hang off (#107).
    struct TypeLookup {
        private var declaredForName: [String: [Declared]] = [:]
        /// Each declaration as recorded, by its identity.
        private(set) var recordForDeclaration: [ObjectIdentifier: RecordedDeclaration] = [:]
        /// The names typealiases are recorded under.
        private(set) var aliasNames: Set<String> = []
        /// A qualifier must name one of these modules to be read as a module (#124).
        private(set) var modules = ModuleQualifiers()

        /// A lookup of every type, extension and typealias in `items`, none of them drawn.
        init(of items: [SyntaxStructure] = []) {
            for item in items {
                guard let kind = item.kind, ElementKind.processable.contains(kind),
                      let name = item.fullName ?? item.name else { continue }
                record(Declared(item, kind: kind, nodeId: nil), named: name)
            }
            recordAliases(in: items)
        }

        mutating func record(_ declared: Declared, named name: String) {
            declaredForName[name, default: []].append(declared)
            if declared.aliasTarget != nil {
                aliasNames.insert(name)
            }
            recordForDeclaration[declared.declaration] = RecordedDeclaration(
                name: name, order: recordForDeclaration.count, declared: declared
            )
            if let module = declared.scope.module {
                modules.record(module)
            }
        }

        /// Records the typealiases among `items` and among their members, a member as
        /// `Container.Alias`, so a name written through one means the type it aliases (#125). Run
        /// after the types are recorded: when nothing else tells two candidates apart, `nearest`
        /// picks the first, and that should be a type.
        mutating func recordAliases(in items: [SyntaxStructure]) {
            for item in items {
                if item.kind == .typealias, let name = item.fullName ?? item.name {
                    record(Declared(item, kind: .typealias, nodeId: nil), named: name)
                }
                guard let kind = item.kind, ElementKind.processable.contains(kind),
                      let containerName = item.fullName ?? item.name else { continue }
                // An alias in `extension ModA.Foo` is also `Foo.Alias`, the name it has once merged.
                let canonical = kind == .extension && readsModule(containerName, from: Scope(of: item))
                    ? recordedName(of: containerName, from: Scope(of: item)) : nil
                for member in item.substructure ?? [] where member.kind == .typealias {
                    guard let name = member.name else { continue }
                    let declared = Declared(member, kind: .typealias, nodeId: nil, in: item)
                    record(declared, named: "\(containerName).\(name)")
                    if let canonical, canonical != containerName {
                        record(declared, named: "\(canonical).\(name)")
                    }
                }
            }
        }

        /// Every declaration recorded under `name`, types, typealiases and extensions, in
        /// recording order.
        func declarations(named name: String) -> [Declared] {
            declaredForName[name] ?? []
        }

        /// The type a name means where it is written, close to how Swift looks it up: the nearest
        /// (`DeclarationScope.nearest(among:scope:)`) of the types and typealiases visible there,
        /// drawn or hidden, and for a typealias the type it aliases, as seen from the alias;
        /// `nil` when there is none, only extensions or nothing, or when the alias names a type
        /// outside the diagram. A typealias ranks with the types, so a module's own alias shadows
        /// an imported type of its name, as in Swift (#125). A name is never matched against
        /// node ids: an undeclared `Foo_1` must not land on the node issued `Foo_1` as the second
        /// declaration of `Foo`.
        func type(named name: String, from scope: Scope, depth: Int = 0) -> Declared? {
            guard let nearest = nearestMatch(named: name, from: scope, depth: depth)?.declared else { return nil }
            guard let target = nearest.aliasTarget else { return nearest }
            // Each step follows one alias; Swift rejects a cycle, and the guard is a backstop.
            guard depth < 8 else { return nil }
            let targetName = qualifiedName(ofWritten: target, from: nearest.scope)
            return type(named: targetName, from: nearest.scope, depth: depth + 1)
        }

        /// The name `name` comes to where it is written once every typealias it goes through is
        /// followed: `Dictionary` for `JSON` after `typealias JSON = [String: Int]`, and otherwise
        /// the name the declaration it means is recorded under — `name` itself, or `Foo` for a
        /// `ModA.Foo` read through its module. Two extensions of one type outside the diagram share
        /// this name however each spells the type. `readingModules: false` reads no module
        /// qualifier, for the text formats' supertype edges, which end on a name and so cannot
        /// tell ModA's `Foo` from another `Foo` (`TypeAliasResolver`).
        func resolvedName(of name: String, from scope: Scope, readingModules: Bool = true, depth: Int = 0) -> String {
            guard depth < 8,
                  let match = nearestMatch(named: name, from: scope, depth: depth, readingModules: readingModules)
            else { return name }
            guard let target = match.declared.aliasTarget else { return match.name }
            let scope = match.declared.scope
            let targetName = qualifiedName(ofWritten: target, from: scope, readingModules: readingModules)
            return resolvedName(of: targetName, from: scope, readingModules: readingModules, depth: depth + 1)
        }

        /// The name a type written as `name` in a declaration's inheritance clause is recorded
        /// under: `<enclosing>.<name>` for the innermost type around the declaration that has
        /// such a member (`DeclarationScope.enclosingTypes`), as Swift looks a name up, and
        /// `name` itself when none does. So `class Near: Base` in `enum Outer` means
        /// `Outer.Base`, even beside a top-level `Base` (#157). An enclosing class's inherited
        /// members are not looked in.
        /// A member is looked for through a module only in a type the declaration's extension
        /// names through one, as `extension ModA.Foo` does: in `extension Settings` the name
        /// `Settings` is a type, even when a target is named `Settings` too.
        func qualifiedName(ofWritten name: String, from scope: Scope, readingModules: Bool = true) -> String {
            let probes = scope.enclosingTypes.lazy.map { enclosing in (enclosing, "\(enclosing).\(name)") }
            return probes.first { enclosing, probe in
                if nearestMatch(named: probe, from: scope, depth: 0, readingModules: false) != nil { return true }
                guard readingModules, mayReadModule(probe), readsModule(enclosing, from: scope) else { return false }
                return moduleMatch(named: probe, from: scope, depth: 0) != nil
            }?.1 ?? name
        }

        /// The nearest of the types and typealiases named `name` that are visible from `scope`.
        /// With none, a name whose first component names a module means the rest of the name in
        /// that module (`moduleMatch`).
        func nearestMatch(
            named name: String, from scope: Scope, depth: Int, readingModules: Bool = true
        ) -> Match? {
            let candidates = declarations(named: name).filter {
                !$0.isExtension && isVisible($0, from: scope, depth: depth)
            }
            if let nearest = scope.nearest(among: candidates, scope: \.scope) {
                return Match(declared: nearest, name: name)
            }
            return readingModules ? moduleMatch(named: name, from: scope, depth: depth) : nil
        }

        /// Whether a name written in `lookup` can mean `declared`, as Swift's access control
        /// allows: a `private` or `fileprivate` type only in its own file, and a type below
        /// `package` only in its own module. A file or module that is unknown on either side is
        /// taken to be the same; parsed sources always carry a file path.
        func isVisible(_ declared: Declared, from lookup: Scope, depth: Int) -> Bool {
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
        /// The drawn extension `mergeExtensions` merged each hidden type's extensions into.
        private var hostForDeclaration: [ObjectIdentifier: String] = [:]
        /// `standIn` and `fallback` for each name, worked out once: searching per edge end made a
        /// diagram of many files that each hide a same-named type cubic in their number.
        private var extensionEnds = ExtensionEnds()

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nodeId), named: entry.name)
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
            if let hidden = entry.item.standsInFor {
                hostForDeclaration[ObjectIdentifier(hidden)] = nodeId
            }
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

        /// Records the typealiases among `items`, the items the diagram was built from, once
        /// every type is recorded (`TypeLookup.recordAliases(in:)`).
        mutating func recordAliases(in items: [SyntaxStructure]) {
            lookup.recordAliases(in: items)
            extensionEnds = ExtensionEnds()
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let written, let scope):
                let name = lookup.qualifiedName(ofWritten: written, from: scope)
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

        /// A drawn extension of the hidden type `declaration`, or `nil` to drop the edge: the one
        /// `mergeExtensions` merged its extensions into, when it did (#153); else the first
        /// recorded under the edge's own name, `name`, whose own lookup finds it, as before #124;
        /// else one recorded under the type's own name, then one spelled with that name qualified
        /// by a module (`ExtensionEnds.qualifiedStandIns`), then one spelled through a typealias.
        /// The access-level filter passes extensions, so an extension can be drawn while its type
        /// is hidden.
        private func standIn(for declaration: ObjectIdentifier, named name: String) -> String? {
            if let host = hostForDeclaration[declaration] { return host }
            if let standIn = extensionEnds.ends(named: name, in: lookup).standIns[declaration] { return standIn }
            guard let recorded = lookup.recordForDeclaration[declaration]?.name else { return nil }
            if recorded != name,
               let standIn = extensionEnds.ends(named: recorded, in: lookup).standIns[declaration] {
                return standIn
            }
            return extensionEnds.qualifiedStandIns(spelling: recorded, in: lookup)[declaration]
                ?? extensionEnds.aliasStandIns(in: lookup)[declaration]
        }

        /// The end for a name no visible type takes, so a type outside the diagram, such as
        /// `String`: the first drawn extension of that same outside type, one whose own lookup
        /// finds no visible type of the name either (#55 pins the first), or `nil` when there is
        /// none. An extension of a type the reference cannot see, a hidden `fileprivate` one,
        /// say, extends something else and never stands in.
        private func fallback(named name: String) -> String? {
            extensionEnds.fallback(named: name, in: lookup)
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
