// MARK: - Sure Kinds

/// A type, and whether its kind is sure (`TypeLookup.typeWithSureKind`).
private typealias SureType = (type: LayoutGraphBuilder.Declared?, isSure: Bool)

/// One lookup of `TypeLookup.typeWithSureKind`: its answer, or the declaration it means, whose
/// type `resolvedType` works out, and what the lookup makes of that, so a chain of typealiases is
/// followed in a loop rather than a call a step (#248).
private enum SureKindLookup {
    case answer(SureType)
    case through(LayoutGraphBuilder.Declared, finish: (SureType) -> SureType)
}

// Whether the kind of the type a name means is sure, kept apart so the type lookup stays a
// readable size. An extension of `TypeLookup` in another file does not see the builder's own
// names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// `type(_:from:depth:)`, and, when that is a protocol, whether it surely is: the nearest
    /// candidate is one in the writer's own file or module, or the only one, or every
    /// candidate comes to a protocol, and a typealias on the way was as sure. Among same-named
    /// types of other modules that a file sees together, which Swift rejects as ambiguous or
    /// settles by a shadowing the lookup does not read, as a re-export's, or of sources read
    /// without their package, the nearest is a guess. A name read through its
    /// module, `ModA.P`, names the module it means. Only a protocol names an edge apart, so no
    /// other kind costs a check. A directory is a guess at a module, so being nearest by one is
    /// not being the writer's own. `kinds` keeps each typealias's kind once worked out, and the
    /// candidates and answer for a writer whose own file does not bear on them
    /// (`ownFileBears(on:_:)`), which then depend on its module, its imports and the type a dotted
    /// name starts at (`QualifiedName.start`) alone, the answer with no module on its directory too
    /// (`SharedLookup`): without them, a name many same-named aliases share looked each alias's
    /// target up for every edge, and every alias of a chain the next one's.
    func typeWithSureKind(
        _ written: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope,
        kinds: LayoutGraphBuilder.AliasKinds,
        depth: Int = 0
    ) -> (type: LayoutGraphBuilder.Declared?, kindIsSure: Bool) {
        let sure: SureType
        switch sureKindLookup(written, from: scope, depth: depth, kinds: kinds) {
        case .answer(let answer): sure = answer
        case let .through(declared, finish): sure = finish(resolvedType(of: declared, depth: depth, kinds: kinds))
        }
        return (sure.type, sure.isSure)
    }

    /// `typeWithSureKind`'s lookup of `written`, short of following the declaration it means.
    private func sureKindLookup(
        _ written: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int,
        kinds: LayoutGraphBuilder.AliasKinds
    ) -> SureKindLookup {
        let name = started(written, from: scope, depth: depth)
        // A member a superclass declares is the one declaration the name means, as is the writer's
        // own candidate, the nearest.
        switch inheritedLookup(name, from: scope, depth: depth) {
        case .member(let inherited):
            return .through(inherited) { resolved in
                resolved.type?.kind == .protocol ? resolved : (resolved.type, true)
            }

        case .hidden:
            return .answer((nil, true))

        case nil:
            break
        }
        if let local = localNearest(name, from: scope, depth: depth),
           !unlistedMemberShadows(local, named: name, from: scope, depth: depth) {
            return .through(local) { resolved in
                resolved.type?.kind == .protocol ? resolved : (resolved.type, true)
            }
        }
        // A hidden nested type in the writer's own file ranks there alone, so its answer is not shared.
        let ownUnlisted = spellings(of: name).contains { spelling in
            unlistedMembers[spelling]?.contains {
                $0.scope.filePath == scope.filePath || $0.rankScope.filePath == scope.filePath
            } == true
        }
        guard let file = scope.filePath, fitsEachAlone(name, from: scope), !ownUnlisted, !ownFileBears(on: name, file),
              !enclosingTypeBears(on: name, from: scope, depth: depth) else {
            let own = LayoutGraphBuilder.SharedLookup(found: candidates(name, from: scope, depth: depth))
            return uncachedLookup(name, among: own, from: scope, depth: depth, kinds: kinds)
        }
        let key = LayoutGraphBuilder.SharedLookupKey(
            name: name.name, root: name.root, isRecorded: name.isRecorded, start: name.start,
            module: scope.module, imports: scope.imports, depth: depth
        )
        let shared = kinds.shared[key]
            ?? LayoutGraphBuilder.SharedLookup(found: candidates(name, from: scope, depth: depth))
        kinds.shared[key] = shared
        let directory = scope.rankingDirectory
        if let known = shared.answerInDirectory[directory] { return .answer((known.type, known.kindIsSure)) }
        switch uncachedLookup(name, among: shared, from: scope, depth: depth, kinds: kinds) {
        case .answer(let answer):
            shared.answerInDirectory[directory] = (answer.type, answer.isSure)
            return .answer(answer)

        case let .through(declared, finish):
            return .through(declared) { resolved in
                let answer = finish(resolved)
                shared.answerInDirectory[directory] = (answer.type, answer.isSure)
                return answer
            }
        }
    }

    /// Whether a type or typealias of `file` can change what `name` means there, so a writer in it
    /// takes no other's answer, nor gives one: under the name, only that file sees one that is
    /// `private`, and it ranks first there. When a module has the name of a dotted name's first
    /// component, the same goes under the rest of the name, for reading that component as the
    /// module (`moduleMatch(named:from:depth:)`), and under the component itself, one only that
    /// file sees keeps it from being read so (`shadows`). What a first component means otherwise is
    /// `QualifiedName.start`, or read only where `fitsEachAlone(_:from:)` is false.
    private func ownFileBears(on name: LayoutGraphBuilder.QualifiedName, _ file: String) -> Bool {
        var names = spellings(of: name)
        if let dot = name.name.firstIndex(of: "."), !modules.modules(namedBy: String(name.name[..<dot])).isEmpty {
            names.append(String(name.name[..<dot]))
            names.append(String(name.name[name.name.index(after: dot)...]))
        }
        return names.contains { filesOfName[$0]?.contains(file) == true }
    }

    /// Whether a type around `scope` can change what the dotted `name` means there in a way its
    /// `SharedLookupKey` does not hold: with no start worked out (`QualifiedName.start`), as in a
    /// file of no known module, a member of it named like a module keeps the first component from
    /// being read as that module (`shadows`), so a writer in it takes no other's answer, nor gives
    /// one (#246).
    private func enclosingTypeBears(
        on name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        guard name.start == nil, let dot = name.name.firstIndex(of: ".") else { return false }
        let first = String(name.name[..<dot])
        return !modules.modules(namedBy: first).isEmpty && isEnclosingMember(first, from: scope, depth: depth)
    }

    private func uncachedLookup(
        _ name: LayoutGraphBuilder.QualifiedName,
        among shared: LayoutGraphBuilder.SharedLookup,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int,
        kinds: LayoutGraphBuilder.AliasKinds
    ) -> SureKindLookup {
        let found = shared.found
        guard let nearest = scope.nearest(among: found, scope: \.rankScope),
              !unlistedMemberShadows(nearest, named: name, from: scope, depth: depth) else {
            guard name.root != .outsideType, let match = moduleMatch(named: name.name, from: scope, depth: depth)
            else { return .answer((nil, true)) }
            return .through(match.declared) { resolved in
                (resolved.type, resolved.type?.kind != .protocol || resolved.isSure)
            }
        }
        let isOwn = scope.filePath.map { $0 == nearest.scope.filePath } == true
            || scope.module.map { $0 == nearest.scope.module } == true
        return .through(nearest) { resolved in
            let type = resolved.type
            guard type?.kind == .protocol else { return (type, true) }
            guard resolved.isSure else { return (type, false) }
            guard found.count > 1, !isOwn else { return (type, true) }
            switch shared.everyComesToProtocol {
            case .every: return (type, true)
            case .notEvery: return (type, false)
            case .unknown: break
            }
            // Each candidate is a lookup of its own, a level deeper with a chain of its own: one step
            // of the writer's chain would make the answer kept for every writer depend on the path to
            // it, and at the same depth with a new chain, a candidate's alias could lead back here
            // for ever.
            let every = found.allSatisfy {
                self.resolvedKind(of: $0, depth: depth + 1, kinds: kinds) == (.protocol, true)
            }
            shared.everyComesToProtocol = every ? .every : .notEvery
            return (type, every)
        }
    }

    /// The kind `declared` comes to, through a typealias the kind of the type it aliases, or
    /// `nil` for one outside the diagram, and whether that is sure (`typeWithSureKind`). Each
    /// step follows one alias, as `aliased(_:depth:readingModules:chain:)` does, so a cycle of them
    /// ends where it comes back to one (`AliasChain`), unsure.
    private func resolvedKind(
        of declared: LayoutGraphBuilder.Declared, depth: Int, kinds: LayoutGraphBuilder.AliasKinds
    ) -> (kind: ElementKind?, isSure: Bool) {
        if declared.aliasTarget != nil, declared.isSugared { return (nil, true) }
        let resolved = resolvedType(of: declared, depth: depth, kinds: kinds)
        return (resolved.type?.kind, resolved.isSure)
    }

    /// `aliased(_:depth:readingModules:chain:)`, and whether the kind of what it comes to is sure,
    /// kept in `kinds` for each typealias: the type is the one `typeWithSureKind` finds for the
    /// alias's target, so a chain's last link, in another file, is looked up once for the writer's
    /// module, not once per alias. Each alias is followed at the same depth, in a loop, so a chain
    /// of any length runs to its end on a stack of one, and a cycle, which Swift rejects, ends
    /// where it comes back to an alias (`AliasChain`), unsure (#248). What each lookup on the way
    /// makes of what comes after it is applied once the end is found, last first, as were the
    /// calls of a lookup a step.
    private func resolvedType(
        of declared: LayoutGraphBuilder.Declared, depth: Int, kinds: LayoutGraphBuilder.AliasKinds
    ) -> (type: LayoutGraphBuilder.Declared?, isSure: Bool) {
        var (current, chain) = (declared, LayoutGraphBuilder.AliasChain())
        var finishes: [(SureType) -> SureType] = []
        var found: SureType
        walk: while true {
            guard let target = current.aliasTarget else {
                found = (current, true)
                break
            }
            if current.isSugared {
                found = (aliased(current, depth: depth, chain: chain), true)
                break
            }
            guard depth < 8, chain.follow(current) else {
                found = (nil, false)
                break
            }
            if let known = kinds[current.declaration, depth] {
                found = known
                break
            }
            let alias = current.declaration
            finishes.append { resolved in
                kinds[alias, depth] = resolved
                return resolved
            }
            let targetName = qualifiedName(ofWritten: target, from: current.scope, depth: depth + 1)
            switch sureKindLookup(targetName, from: current.scope, depth: depth, kinds: kinds) {
            case .answer(let answer):
                found = answer
                break walk

            case let .through(meant, finish):
                finishes.append(finish)
                current = meant
            }
        }
        for finish in finishes.reversed() {
            found = finish(found)
        }
        return found
    }
}
