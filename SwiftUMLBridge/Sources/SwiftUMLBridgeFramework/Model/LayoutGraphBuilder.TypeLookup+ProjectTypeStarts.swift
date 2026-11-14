// MARK: - Project Type Starts

/// What one step of `TypeLookup.startsAtProjectType(_:from:depth:)` makes of a name: whether it
/// is the project's, or the names to judge in its place.
private enum DecidingStep {
    case decided(Bool)
    case through([NameToJudge])
}

/// A name `TypeLookup.startsAtProjectType(_:from:depth:)` has judged, so a name two paths come to
/// is judged once.
private struct JudgedName: Hashable {
    let name: String
    let decider: ObjectIdentifier?
}

/// A typealias one step of `TypeLookup.startsAtProjectType(_:from:depth:)` followed, with how many
/// parts came after it then. While every later name keeps as many after its own deciding part,
/// the walk has not read into them, so deciding the alias again is a cycle, which Swift rejects:
/// `X.Y` after `typealias X = X.Y`. Once a step reads into them, the alias may decide again,
/// legally: `D.Inner`, `Outer.Inner`, `D.Y` after `typealias D = Outer` and
/// `struct Outer { typealias Inner = D.Y; struct Y {} }`.
private struct DecidedAlias {
    let alias: ObjectIdentifier
    let partsAfter: Int
}

/// A name `TypeLookup.startsAtProjectType(_:from:depth:)` judges, with the scope it is read in, the
/// alias whose target it was read from, and the aliases decided on the way whose parts after them
/// are still whole (`DecidedAlias`).
private struct NameToJudge {
    let name: String
    let scope: LayoutGraphBuilder.Scope
    let decider: ObjectIdentifier?
    let decided: [DecidedAlias]

    /// The name judged once in a search: the scope is the decider's, or the search's own.
    var key: JudgedName { JudgedName(name: name, decider: decider) }
}

// Whether a name an extension writes its type with starts at a type the project declares, kept
// apart so the type lookup stays a readable size. An extension of `TypeLookup` in another file
// does not see the builder's own names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// Whether `name`, written in `scope`, is a type the project declares or a member of one, as
    /// far as the lookup can tell. A name the lookup finds, through any typealiases, is the
    /// project's, wherever the type is nested: `Date.Box` after `extension Date { struct Box {} }`,
    /// whose own members Swift looks a name up among, never `Date`'s, and `Outer.Alias` after
    /// `struct Outer { struct Inner {}; typealias Alias = Inner }`. Otherwise the longest leading
    /// part of it that the project declares decides, a nested type the items do not list
    /// included (`unlistedMembers`): a type is the project's, and a typealias is as its target,
    /// read as the lookup reads it and followed by the parts after it, is. So `Crate.Inner`
    /// after `typealias Crate = Outer` is judged as `Outer.Inner`, the project's, and `Crate.D`
    /// after `struct Outer { typealias D = Date }` as `Date`, which is not, nor is `Day` after
    /// `typealias Day = Date`. A name no part of which the project declares is a type outside the
    /// diagram; a first part that is the scope's own module is skipped, as in
    /// `extension MyModule.Outer`. Only the deciding part's alias is followed, so this costs a
    /// lookup a part for each alias on the way, each at the same depth (#248). A name two
    /// readings come to is judged once, and a cycle ends where it decides an alias again before
    /// reading into the parts after it (`DecidedAlias`).
    func startsAtProjectType(
        _ name: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        // The names still to judge, last first: a stack rather than a call an alias, so a long
        // chain takes no more stack than a short one. The answer is whether any reading is the
        // project's, so a name judged on one path is not judged again on another, and a chain
        // whose every link reads two ways costs a step a name, not a step a path.
        var pending = [NameToJudge(name: name, scope: scope, decider: nil, decided: [])]
        var judged: Set<JudgedName> = []
        while let next = pending.popLast() {
            guard judged.insert(next.key).inserted else { continue }
            switch decidingStep(of: next, depth: depth) {
            case .decided(true): return true
            case .decided(false): continue
            case .through(let names): pending += names.reversed()
            }
        }
        return false
    }

    /// What one step of `startsAtProjectType(_:from:depth:)` makes of `judging`'s name: whether it
    /// is the project's, or the names its deciding typealias stands for, nearest first, read where
    /// the alias is.
    private func decidingStep(of judging: NameToJudge, depth: Int) -> DecidingStep {
        let scope = judging.scope
        var parts = judging.name.split(separator: ".").map(String.init)
        if parts.count > 1, parts[0] == scope.module,
           nearestVisible(named: parts[0], from: scope, depth: depth) == nil {
            parts.removeFirst()
        }
        if type(named: parts.joined(separator: "."), from: scope, depth: depth) != nil { return .decided(true) }
        var prefix = ""
        var deciding: LayoutGraphBuilder.Declared?
        var used = 0
        for (index, part) in parts.enumerated() {
            prefix = prefix.isEmpty ? part : "\(prefix).\(part)"
            guard let nearest = nearestVisible(named: prefix, from: scope, depth: depth)
                ?? nearestUnlisted(named: prefix, from: scope, depth: depth)
            else { continue }
            deciding = nearest
            used = index + 1
        }
        guard let deciding else { return .decided(false) }
        guard let target = deciding.aliasTarget else { return .decided(true) }
        // The parts after the deciding alias are members of what it stands for.
        let tail = Array(parts.dropFirst(used))
        // The aliases decided before whose parts after them this step has not read into.
        let whole = judging.decided.filter { $0.partsAfter <= tail.count }
        let decider = ObjectIdentifier(deciding)
        guard !deciding.isSugared, depth < 8, !whole.contains(where: { $0.alias == decider }) else {
            return .decided(false)
        }
        let decided = whole + [DecidedAlias(alias: decider, partsAfter: tail.count)]
        var names: [NameToJudge] = []
        // A target nested beside the alias that the lookup does not record, as while nested types
        // are hidden, is one of the unlisted members of the alias's container or of a type around
        // it: `Stamp = Real` in `Box.Inner` is `Box.Inner.Real`.
        if let unlisted = unlistedTarget(target, around: Array(parts.prefix(used - 1))) {
            let unlistedName = ([unlisted] + tail).joined(separator: ".")
            names.append(NameToJudge(name: unlistedName, scope: deciding.scope, decider: decider, decided: decided))
        }
        let written = qualifiedName(ofWritten: target, from: deciding.scope, depth: depth + 1)
        let writtenName = ([written.name] + tail).joined(separator: ".")
        names.append(NameToJudge(name: writtenName, scope: deciding.scope, decider: decider, decided: decided))
        return .through(names)
    }

    /// `target`, written in the container `container` names, as the full name of an unlisted
    /// member (`unlistedMembers`) of that container or of a type around it, innermost first.
    private func unlistedTarget(_ target: String, around container: [String]) -> String? {
        guard !container.isEmpty, !unlistedMembers.isEmpty else { return nil }
        var targetParts = target.split(separator: ".").map(String.init)
        guard !targetParts.isEmpty else { return nil }
        let head = targetParts.removeFirst()
        for count in stride(from: container.count, to: 0, by: -1) {
            let candidate = (container.prefix(count) + [head]).joined(separator: ".")
            if unlistedMembers[candidate] != nil { return ([candidate] + targetParts).joined(separator: ".") }
        }
        return nil
    }

    /// The nearest type or typealias recorded under `name` exactly that `scope` sees, as
    /// `DeclarationScope.nearest(among:scope:)` picks it: one in `scope`'s own file first, found
    /// without the rest, so a name a thousand files each declare privately costs no scan of them.
    private func nearestVisible(
        named name: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.Declared? {
        if let filePath = scope.filePath,
           let local = typesForNameInFile[name]?[filePath]?.first(where: { isVisible($0, from: scope, depth: depth) }) {
            return local
        }
        let visible = (typesForName[name] ?? []).filter { isVisible($0, from: scope, depth: depth) }
        return scope.nearest(among: visible, scope: \.rankScope)
    }

    /// The nearest nested type or typealias the items do not list (`unlistedMembers`) under
    /// `name` that `scope` sees, ranked as `nearestVisible(named:from:depth:)` ranks recorded
    /// ones, so the answer never turns on the order the paths are read in (#232): with nested
    /// types hidden, `Box.Inner.Stamp` written in `Near/` is Near's own struct, not a
    /// `typealias Stamp = Date` that `Far/` hides under the same name.
    private func nearestUnlisted(
        named name: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.Declared? {
        let visible = (unlistedMembers[name] ?? []).filter { isVisible($0, from: scope, depth: depth) }
        return scope.nearest(among: visible, scope: \.rankScope)
    }
}
