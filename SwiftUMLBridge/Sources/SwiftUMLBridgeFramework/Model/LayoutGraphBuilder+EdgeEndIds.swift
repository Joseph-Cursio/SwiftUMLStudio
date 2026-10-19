import Foundation

// MARK: - Edge End Ids

/// Where `buildClassDiagram` ends each edge, kept apart so the type lookup stays a readable size.
extension LayoutGraphBuilder {
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
        private var aliasKinds = AliasKinds()

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nodeId), named: entry.name)
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
            if let hidden = entry.item.standsInFor {
                hostForDeclaration[ObjectIdentifier(hidden)] = nodeId
            }
            forgetWorkedOutEnds()
        }

        /// Records a type the diagram hides. A hidden extension is simply gone: only a type can
        /// be what a name means.
        mutating func recordHidden(_ entry: DiagramItem) {
            guard entry.kind != .extension else { return }
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nil), named: entry.name)
            hiddenDeclarations.insert(ObjectIdentifier(entry.item))
            forgetWorkedOutEnds()
        }

        /// Records the typealiases among `items`, the items the diagram was built from, once
        /// every type is recorded (`TypeLookup.recordAliases(in:)`).
        mutating func recordAliases(in items: [SyntaxStructure]) {
            lookup.recordAliases(in: items)
            forgetWorkedOutEnds()
        }

        /// Drops what was worked out from the declarations recorded so far, once another is.
        private mutating func forgetWorkedOutEnds() {
            extensionEnds = ExtensionEnds()
            aliasKinds = AliasKinds()
        }

        /// What a supertype written as `written` in `scope` resolves to: the node id its edge ends
        /// on, as `id(of:)` has it, and whether the edge is a realization, the type the name means,
        /// drawn or hidden, being a protocol. The kind counts when it is sure
        /// (`TypeLookup.typeWithSureKind(_:from:)`), or when the edge ends on that protocol's own
        /// box, whose shape says what it is anyway; a type outside the diagram is no protocol.
        func supertype(named written: String, from scope: Scope) -> (id: String?, isProtocol: Bool) {
            let name = lookup.qualifiedName(ofWritten: written, from: scope)
            let (type, kindIsSure) = lookup.typeWithSureKind(name, from: scope, kinds: aliasKinds)
            guard let type else {
                return (fallback(named: name.name, resolving: lookup.sureResolvedName(of: name, from: scope)), false)
            }
            return (node(for: type, named: name.name), type.kind == .protocol && (kindIsSure || type.nodeId != nil))
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let written, let scope):
                let name = lookup.qualifiedName(ofWritten: written, from: scope)
                guard let type = lookup.type(name, from: scope) else {
                    return fallback(named: name.name, resolving: lookup.sureResolvedName(of: name, from: scope))
                }
                return node(for: type, named: name.name)
            case .declaration(let declaration, let name, let scope):
                if let nodeId = idForDeclaration[declaration] { return nodeId }
                if hiddenDeclarations.contains(declaration) { return standIn(for: declaration, named: name) }
                guard let type = lookup.type(named: name, from: scope) else {
                    let written = QualifiedName(name: name, root: .asWritten)
                    return fallback(named: name, resolving: lookup.sureResolvedName(of: written, from: scope))
                }
                return node(for: type, named: name)
            case .extended(let declaration, let name, let scope, let isSugared):
                // With no type of that name visible there, the extension stands for itself.
                guard let type = lookup.extendedType(named: name, from: scope, isSugared: isSugared) else {
                    if let nodeId = idForDeclaration[declaration] { return nodeId }
                    return fallback(named: name, resolving: lookup.resolvedExtendedName(
                        named: name, from: scope, isSugared: isSugared
                    ))
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
        /// by a module (`ExtensionEnds.qualifiedStandIns`), then the first written through a
        /// typealias of it. The access-level filter passes extensions, so an extension can be
        /// drawn while its type is hidden.
        private func standIn(for declaration: ObjectIdentifier, named name: String) -> String? {
            if let host = hostForDeclaration[declaration] { return host }
            if let standIn = extensionEnds.ends(named: name, in: lookup).standIns[declaration] { return standIn }
            guard let recorded = lookup.recordedName(of: declaration) else { return nil }
            if recorded != name,
               let standIn = extensionEnds.ends(named: recorded, in: lookup).standIns[declaration] {
                return standIn
            }
            return extensionEnds.qualifiedStandIns(spelling: recorded, in: lookup)[declaration]
                ?? extensionEnds.aliasSpelled(in: lookup).standIns[declaration]
        }

        /// The end for a name no visible type takes, so a type outside the diagram, such as
        /// `String`: the first drawn extension of that same outside type, one whose own lookup
        /// finds no visible type of the name either (#55 pins the first), or `nil` when there is
        /// none. One recorded under `name` comes first, then one recorded under the name the type
        /// comes to, `resolved` (`TypeLookup.sureResolvedName(of:from:depth:)`), then one written
        /// through a typealias that comes to it, as `mergeExtensions` gives that type one box:
        /// `struct T: CustomStringConvertible` ends on `extension Describable` after
        /// `typealias Describable = CustomStringConvertible` (#125). A name no typealias takes is
        /// trusted as written, as the first step trusts it, so `resolved` is worked out only for
        /// one a typealias takes; with no sure name for it, as written in an extension of a type
        /// outside the diagram, where it may be that type's member, only `name` counts. An
        /// extension of a type the reference cannot see, a hidden `fileprivate` one, say, extends
        /// something else and never stands in.
        private func fallback(named name: String, resolving resolved: @autoclosure () -> String?) -> String? {
            if let fallback = extensionEnds.ends(named: name, in: lookup).fallback { return fallback }
            guard lookup.namesTypealias(name) else { return extensionEnds.aliasSpelled(in: lookup).fallbacks[name] }
            guard let resolved = resolved() else { return nil }
            if resolved != name, let fallback = extensionEnds.ends(named: resolved, in: lookup).fallback {
                return fallback
            }
            return extensionEnds.aliasSpelled(in: lookup).fallbacks[resolved]
        }
    }
}
