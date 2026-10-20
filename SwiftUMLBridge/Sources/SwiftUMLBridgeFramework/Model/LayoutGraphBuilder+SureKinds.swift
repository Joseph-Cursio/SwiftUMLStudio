import Foundation

// MARK: - Sure Kinds

// Whether the kind of the type a name means is sure, kept apart so the type lookup stays a
// readable size. An extension of `TypeLookup` in another file does not see the builder's own
// names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// `type(_:from:depth:)`, and, when that is a protocol, whether it surely is: the nearest
    /// candidate is one in the writer's own file or module, or the only one, or every
    /// candidate comes to a protocol, and a typealias on the way was as sure. A file's imports
    /// are read only for module qualifiers, so among same-named types of other modules the
    /// nearest is a guess, which may be one the writer does not import. A name read through its
    /// module, `ModA.P`, names the module it means. Only a protocol names an edge apart, so no
    /// other kind costs a check. `kinds` keeps each typealias's kind once worked out, and the
    /// answer for a writer with no candidate in its own file, which depends on its module and
    /// imports alone: without them, a name many same-named aliases share looked each alias's
    /// target up for every edge, and every alias of a chain the next one's.
    func typeWithSureKind(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int = 0,
        kinds: LayoutGraphBuilder.AliasKinds
    ) -> (type: LayoutGraphBuilder.Declared?, kindIsSure: Bool) {
        // The writer's own candidate is the nearest, and surely the one it means.
        if let local = localNearest(name, from: scope, depth: depth),
           !unlistedMemberShadows(local, named: name, from: scope, depth: depth) {
            let resolved = resolvedType(of: local, depth: depth, kinds: kinds)
            guard resolved.type?.kind == .protocol else { return (resolved.type, true) }
            return (resolved.type, resolved.isSure)
        }
        // A hidden nested type in the writer's own file ranks there alone, so its answer is not shared.
        let ownUnlisted = unlistedMembers[name.name]?.contains {
            $0.scope.filePath == scope.filePath || $0.rankScope.filePath == scope.filePath
        } == true
        guard scope.filePath != nil, fitsEachAlone(name), !ownUnlisted else {
            return uncachedTypeWithSureKind(name, from: scope, depth: depth, kinds: kinds)
        }
        let key = LayoutGraphBuilder.SharedLookupKey(
            name: name.name, root: name.root, isRecorded: name.isRecorded, module: scope.module,
            imports: scope.imports, depth: depth
        )
        if let known = kinds.shared[key] { return known }
        let result = uncachedTypeWithSureKind(name, from: scope, depth: depth, kinds: kinds)
        kinds.shared[key] = result
        return result
    }

    private func uncachedTypeWithSureKind(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int,
        kinds: LayoutGraphBuilder.AliasKinds
    ) -> (type: LayoutGraphBuilder.Declared?, kindIsSure: Bool) {
        let found = candidates(name, from: scope, depth: depth)
        guard let nearest = scope.nearest(among: found, scope: \.rankScope),
              !unlistedMemberShadows(nearest, named: name, from: scope, depth: depth) else {
            guard name.root != .outsideType, let match = moduleMatch(named: name.name, from: scope, depth: depth)
            else { return (nil, true) }
            let resolved = resolvedType(of: match.declared, depth: depth, kinds: kinds)
            return (resolved.type, resolved.type?.kind != .protocol || resolved.isSure)
        }
        let resolved = resolvedType(of: nearest, depth: depth, kinds: kinds)
        let type = resolved.type
        guard type?.kind == .protocol else { return (type, true) }
        guard resolved.isSure else { return (type, false) }
        let isOwn = scope.filePath.map { $0 == nearest.scope.filePath } == true
            || scope.module.map { $0 == nearest.scope.module } == true
        guard found.count > 1, !isOwn else { return (type, true) }
        return (type, found.allSatisfy { resolvedKind(of: $0, depth: depth, kinds: kinds) == (.protocol, true) })
    }

    /// The kind `declared` comes to, through a typealias the kind of the type it aliases, or
    /// `nil` for one outside the diagram, and whether that is sure (`typeWithSureKind`). Each
    /// step follows one alias, as `aliased(_:depth:readingModules:)` does, so a cycle of them ends
    /// at the same depth guard, unsure.
    private func resolvedKind(
        of declared: LayoutGraphBuilder.Declared, depth: Int, kinds: LayoutGraphBuilder.AliasKinds
    ) -> (kind: ElementKind?, isSure: Bool) {
        if declared.aliasTarget != nil, declared.isSugared { return (nil, true) }
        let resolved = resolvedType(of: declared, depth: depth, kinds: kinds)
        return (resolved.type?.kind, resolved.isSure)
    }

    /// `aliased(_:depth:readingModules:)`, and whether the kind of what it comes to is sure, kept
    /// in `kinds` for each typealias: the type is the one `typeWithSureKind` finds for the alias's
    /// target, so a chain's last link, in another file, is looked up once for the writer's
    /// module, not once per alias.
    private func resolvedType(
        of declared: LayoutGraphBuilder.Declared, depth: Int, kinds: LayoutGraphBuilder.AliasKinds
    ) -> (type: LayoutGraphBuilder.Declared?, isSure: Bool) {
        guard let target = declared.aliasTarget else { return (declared, true) }
        if declared.isSugared { return (aliased(declared, depth: depth), true) }
        guard depth < 8 else { return (nil, false) }
        if let known = kinds[declared.declaration, depth] { return known }
        let targetName = qualifiedName(ofWritten: target, from: declared.scope, depth: depth + 1)
        let (type, isSure) = typeWithSureKind(targetName, from: declared.scope, depth: depth + 1, kinds: kinds)
        kinds[declared.declaration, depth] = (type, isSure)
        return (type, isSure)
    }
}
