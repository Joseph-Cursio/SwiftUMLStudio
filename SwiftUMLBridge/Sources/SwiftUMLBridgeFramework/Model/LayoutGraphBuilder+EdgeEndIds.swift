import Foundation

// MARK: - Edge End Ids

/// Where `buildClassDiagram` ends each edge, kept apart so the type lookup stays a readable size.
extension LayoutGraphBuilder {
    /// The node ids an `EdgeEnd` can resolve to, gathered while the nodes are built.
    struct EdgeEndIds {
        private var lookup = TypeLookup()
        private var idForDeclaration: [ObjectIdentifier: String] = [:]
        private var hiddenDeclarations: Set<ObjectIdentifier> = []
        /// `standIn` and `fallback` for each name, worked out once: searching per edge end made a
        /// diagram of many files that each hide a same-named type cubic in their number.
        private var extensionEnds = ExtensionEnds()
        private var aliasKinds = AliasKinds()

        mutating func record(_ nodeId: String, for entry: DiagramItem) {
            lookup.record(Declared(entry.item, kind: entry.kind, nodeId: nodeId), named: entry.name)
            idForDeclaration[ObjectIdentifier(entry.item)] = nodeId
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
            guard let type else { return (fallback(named: name.name), false) }
            return (node(for: type, named: name.name), type.kind == .protocol && (kindIsSure || type.nodeId != nil))
        }

        func id(of end: EdgeEnd) -> String? {
            switch end {
            case .node(let nodeId):
                return nodeId
            case .named(let written, let scope):
                let name = lookup.qualifiedName(ofWritten: written, from: scope)
                guard let type = lookup.type(name, from: scope) else { return fallback(named: name.name) }
                return node(for: type, named: name.name)
            case .declaration(let declaration, let name, let scope):
                if let nodeId = idForDeclaration[declaration] { return nodeId }
                if hiddenDeclarations.contains(declaration) { return standIn(for: declaration, named: name) }
                guard let type = lookup.type(named: name, from: scope) else {
                    return fallback(named: name)
                }
                return node(for: type, named: name)
            case .extended(let declaration, let name, let scope, let isSugared):
                // With no type of that name visible there, the extension stands for itself.
                guard let type = lookup.extendedType(named: name, from: scope, isSugared: isSugared) else {
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
}
