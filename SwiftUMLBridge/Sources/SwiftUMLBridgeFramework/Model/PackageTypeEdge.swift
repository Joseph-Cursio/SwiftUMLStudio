/// A type name and the module that declares the type.
private struct DeclaredName: Hashable {
    let name: String
    let module: String

    /// The name spelled with its module, as Swift code writes it: its C99 name, so target
    /// `changelog-authors` gives `changelog_authors.Author`.
    var qualified: String { "\(ModuleQualifiers.c99Name(of: module)).\(name)" }
}

/// A `deps --types` edge with the module that declares the type at each end, which a type
/// outside the package has none of, even when an extension gives its end a tag
/// (`PackageTypeOwners.extendingModule(of:)`). Loose files declare no module.
struct PackageTypeEdge {
    let edge: DependencyEdge
    /// The module that declares the type `edge.from` names; nil for a type outside the package.
    let fromDeclaring: String?
    /// The module that declares the type `edge.toNode` names; nil for a type outside the package.
    let toDeclaring: String?

    /// `edges` with each type that shares its name with another module's spelled with its
    /// module, as Swift spells it to tell them apart: where ModA and ModB each declare a `Base`
    /// and both are edge ends, ModA's ends become `ModA.Base` and ModB's `ModB.Base`, two nodes
    /// with their own edges and tags. Nodes are keyed by name, so the two used to share one
    /// node, which carried one module's tag on the other's edges too (#202).
    ///
    /// The module is spelled as Swift code writes it, its C99 name, so target `changelog-authors`
    /// gives `changelog_authors.Author`; the tag keeps the target's own name.
    ///
    /// A name is split only where its ends mean types of more than one module, or of one module
    /// and none: ModA's own `Identifiable` beside Swift's becomes `ModA.Identifiable`, and
    /// Swift's keeps its name, with any tag an extension gives it. A type outside the package
    /// is never spelled with a module, as no module of the package declares it. Every other
    /// name is left as it comes, so a package whose types all have names of their own, and that
    /// declares no type of a name outside the package it uses, keeps every name.
    ///
    /// An end written with its module, `ModB.Base`, already comes as `Base` declared by ModB, so
    /// it meets ModB's node. An end left dotted is a nested type, as `ModA.Base` in an
    /// `enum ModA`; where that spelling is a split node's, it is spelled with its own module too,
    /// `ModA.ModA.Base`, as Swift spells it, and so on until no two of the package's types share
    /// a spelling. Only a type outside the package, which has no module to spell it with, can
    /// still meet a package type's node.
    ///
    /// An edge is left out where `isExcluded` holds for an end's name as it comes or spelled with
    /// its module, which a drawn name always is one of, so `--exclude ModB.Base` hides ModB's
    /// `Base` however it is written or drawn. Names are chosen before any edge is left out, so
    /// excluding one type renames no other.
    static func drawn(_ edges: [Self], excluding isExcluded: (String) -> Bool = { _ in false }) -> [DependencyEdge] {
        var modules: [String: Set<String?>] = [:]
        for typeEdge in edges {
            modules[typeEdge.edge.from, default: []].insert(typeEdge.fromDeclaring)
            modules[typeEdge.edge.toNode, default: []].insert(typeEdge.toDeclaring)
        }
        let declared = modules.flatMap { name, declaring in
            declaring.compactMap { $0.map { DeclaredName(name: name, module: $0) } }
        }
        // A shared name's declared ends are spelled with their modules, then each declared end
        // whose name is one of those spellings, until none is.
        var spelledWithModule = Set(declared.filter { modules[$0.name, default: []].count > 1 })
        while true {
            let taken = Set(spelledWithModule.map(\.qualified))
            let clashing = declared.filter { !spelledWithModule.contains($0) && taken.contains($0.name) }
            guard !clashing.isEmpty else { break }
            spelledWithModule.formUnion(clashing)
        }
        func spelled(_ name: String, in module: String?) -> String {
            guard let module else { return name }
            let end = DeclaredName(name: name, module: module)
            return spelledWithModule.contains(end) ? end.qualified : name
        }
        func excludes(_ name: String, in module: String?) -> Bool {
            isExcluded(name) || module.map { isExcluded(DeclaredName(name: name, module: $0).qualified) } == true
        }
        return edges.compactMap { typeEdge in
            let named = typeEdge.edge
            let from = spelled(named.from, in: typeEdge.fromDeclaring)
            let toNode = spelled(named.toNode, in: typeEdge.toDeclaring)
            guard !excludes(named.from, in: typeEdge.fromDeclaring),
                  !excludes(named.toNode, in: typeEdge.toDeclaring) else { return nil }
            return DependencyEdge(
                from: from, toNode: toNode, kind: named.kind, fromModule: named.fromModule, toModule: named.toModule
            )
        }
    }
}
