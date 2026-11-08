import Foundation

// MARK: - Resolved Names

// The names typealiases come to, for matching extensions of one type however each spells it,
// kept apart so the type lookup stays a readable size. An extension of `TypeLookup` in another
// file does not see the builder's own names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// Whether a typealias is recorded under `name`, so an extension written with it extends a
    /// type recorded under another name.
    func namesTypealias(_ name: String) -> Bool {
        aliasNames.contains(name)
    }

    /// `resolvedName(of:from:depth:)` when the type the name comes to is sure, else `nil`. Swift
    /// looks a name written inside an extension of a type outside the diagram up among that
    /// type's members first, which the lookup cannot see, so a name, or an alias's target,
    /// written there that nothing the project declares takes may be one of them:
    /// `typealias Style = FormatStyle` in `extension Date` is `Date.FormatStyle`, not
    /// Foundation's protocol `FormatStyle`. A name the project declares is taken as the lookup
    /// takes it everywhere else, so `Describable` written there is the project's typealias. A
    /// name the lookup finds nothing for comes to its spelling through its first component's
    /// typealias (`spelledThroughStart(_:from:depth:)`). Each typealias is followed at the same
    /// depth, in a loop, as `resolvedName(of:from:readingModules:depth:)` follows it, and what a
    /// walk from each comes to is kept (`AliasWalks`) (#248).
    func sureResolvedName(
        of name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int = 0
    ) -> String? {
        guard depth < 8 else { return name.name }
        var (name, scope, chain) = (name, scope, LayoutGraphBuilder.AliasChain())
        var followed: [LayoutGraphBuilder.Declared] = []
        let resolved: String?
        while true {
            let match = nearestMatch(name, from: scope, depth: depth)
            if match == nil, name.root == .asWritten, mayMeanOutsideMember(from: scope, depth: depth) {
                resolved = nil
                break
            }
            guard let match else {
                resolved = spelledThroughStart(name, from: scope, depth: depth) ?? name.name
                break
            }
            let alias = match.declared
            guard let target = alias.aliasTarget, !alias.isSugared else {
                resolved = alias.aliasTarget ?? match.name
                break
            }
            if let known = aliasSureNames.entry(for: alias, depth: depth, readingModules: true) {
                resolved = known.value
                break
            }
            // A cycle's answer turns on where the walk came into it, so it is not kept.
            guard chain.follow(alias) else { return name.name }
            followed.append(alias)
            scope = alias.scope
            name = qualifiedName(ofWritten: target, from: scope, depth: depth + 1)
        }
        for alias in followed {
            aliasSureNames.record(resolved, for: alias, depth: depth, readingModules: true)
        }
        return resolved
    }

    /// Whether a name written in `scope` may be a member of a type outside the diagram: it is
    /// written in an extension of sugar, or of a type the project does not declare
    /// (`startsAtProjectType(_:from:depth:)`).
    private func mayMeanOutsideMember(from scope: LayoutGraphBuilder.Scope, depth: Int) -> Bool {
        guard let enclosing = scope.enclosingExtension else { return false }
        guard !enclosing.isSugared else { return true }
        // An extension's own clause sees no enclosing types, only its file, module and imports.
        let clause = scope.fileScope
        return !startsAtProjectType(enclosing.name, from: clause, depth: depth)
    }

    /// Whether a nested type the items do not list (`unlistedMembers`), as while nested types are
    /// hidden, is what `name` means from `scope` rather than `nearest`: it ranks nearer, as it
    /// would were it recorded, a type before a typealias among equals, as recording types first
    /// makes it. Such a name finds no end, as one with no candidate does: in ModB, `Foo.V` is
    /// ModB's own hidden `struct Foo { class V {} }`, never `typealias V = Base` in ModB's
    /// `extension ModA.Foo`, which the lookup also records as `Foo.V`. The rivals are fitted
    /// beside `nearest`, as recorded they would be: `Array.Box` after a project
    /// `struct Array { typealias Box = Base }` never means a `class Box` hidden in
    /// `extension [Int]`, and `nearest` is passed over when it is of the root the name does not mean.
    func unlistedMemberShadows(
        _ nearest: LayoutGraphBuilder.Declared, named name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        let unlisted = spellings(of: name).flatMap { unlistedMembers[$0] ?? [] }
        guard name.root != .outsideType, !unlisted.isEmpty else { return false }
        let visible = unlisted.filter {
            $0.declaration != nearest.declaration && isVisible($0, from: scope, depth: depth)
        }
        guard !visible.isEmpty else { return false }
        let fitted = fitting([nearest] + visible, for: name, from: scope, depth: depth)
        let rivals = fitted.filter { $0.declaration != nearest.declaration }
        guard !rivals.isEmpty else { return false }
        guard rivals.count < fitted.count else { return true }
        let ranked = nearest.aliasTarget == nil ? [nearest] + rivals : rivals + [nearest]
        return scope.nearest(among: ranked, scope: \.rankScope)?.declaration != nearest.declaration
    }

    /// The name the type an extension around `scope` extends is recorded under, when the
    /// extension spells it through a typealias: `Outer` inside `extension Crate` after
    /// `typealias Crate = Outer`, whose body sees `Outer`'s members (`qualifiedName(ofWritten:)`).
    /// `nil` for any other scope, which costs no lookup: no leading part of the extension's name
    /// is a typealias.
    func extendedTypeName(around scope: LayoutGraphBuilder.Scope, depth: Int) -> String? {
        guard let enclosing = scope.enclosingExtension, !enclosing.isSugared, depth < 8 else { return nil }
        let parts = enclosing.name.split(separator: ".")
        guard (1...parts.count).contains(where: { aliasNames.contains(parts.prefix($0).joined(separator: ".")) })
        else { return nil }
        let clause = scope.fileScope
        if let type = extendedType(named: enclosing.name, from: clause, isSugared: false, depth: depth + 1) {
            guard let recorded = recordedName(of: type.declaration), recorded != enclosing.name else { return nil }
            return recorded
        }
        // A type outside the diagram: the name it comes to, `Date` for `extension Day` after
        // `typealias Day = Date`, under which the members its other extensions declare are recorded.
        let written = LayoutGraphBuilder.QualifiedName(name: enclosing.name, root: .asWritten)
        guard let resolved = sureResolvedName(of: written, from: clause, depth: depth + 1),
              resolved != enclosing.name else { return nil }
        return resolved
    }

    /// Records the typealiases among `items` and among their members, a member as
    /// `Container.Alias`, so a name written through one means the type it aliases (#125). Run
    /// after the types are recorded: when nothing else tells two candidates apart, `nearest`
    /// picks the first, and that should be a type. A typealias that an extension merged into
    /// its container declares (`SyntaxStructure.mergedExtensions`) is read where that extension
    /// declares it, as when the extensions are drawn apart, and ranks by `memberRank`. It is
    /// recorded under the extension's own spelling too: `extension Crate { typealias Desc }`
    /// merged into `struct Outer` makes both `Outer.Desc` and `Crate.Desc`. The nested types the
    /// items do not list are kept apart (`unlistedMembers`), and the modules each module loads
    /// are read from `items` (`moduleLoads`).
    mutating func recordAliases(in items: [SyntaxStructure]) {
        moduleLoads = ModuleLoads(of: items)
        for item in items {
            if item.kind == .typealias, let name = item.fullName ?? item.name {
                record(LayoutGraphBuilder.Declared(item, kind: .typealias, nodeId: nil), named: name)
            }
            guard let kind = item.kind, ElementKind.processable.contains(kind),
                  let containerName = item.fullName ?? item.name else { continue }
            let origins = item.mergedMemberOrigins
            for member in item.substructure ?? [] where member.kind == .typealias {
                guard let name = member.name else { continue }
                record(mergedAlias(member, in: item, from: origins[ObjectIdentifier(member)]),
                       named: "\(containerName).\(name)")
            }
            recordMergedAliases(of: item, named: containerName)
            let unlisted = unlistedMembers(of: item, named: containerName)
            unlistedMembers.merge(unlisted) { $0 + $1 }
            for (name, members) in unlisted where members.contains(where: { $0.extended != nil }) {
                unlistedNamesWithExtendedTypes.insert(name)
            }
        }
        for item in items where item.kind == .extension { recordAliasSpelledMembers(of: item) }
    }

    /// Records each typealias an extension declares under the name of the type it extends too,
    /// when it spells that type through a typealias or a module, as merging it does
    /// (`recordMergedAliases`), ranked by `memberRank`: after `extension Crate { typealias
    /// D = Date }`, `Outer.D` is `Date` drawn apart as well, and an alias in `extension ModA.Foo`
    /// is also `Foo.Alias`. Spelled through a module, it is also recorded under the name the
    /// declaration the spelling means is recorded under, before any typealias is followed:
    /// `FA.Alias` in `extension ModA.FA`.
    private mutating func recordAliasSpelledMembers(of anExtension: SyntaxStructure) {
        let aliases = (anExtension.substructure ?? []).filter { $0.kind == .typealias }
        guard !aliases.isEmpty, !anExtension.isSugared, let spelling = anExtension.fullName ?? anExtension.name
        else { return }
        let scope = LayoutGraphBuilder.Scope(of: anExtension)
        let parts = spelling.split(separator: ".")
        let throughAlias = (1...parts.count).contains { aliasNames.contains(parts.prefix($0).joined(separator: ".")) }
        let throughModule = readsModule(spelling, from: scope)
        guard throughAlias || throughModule,
              let type = extendedType(named: spelling, from: scope, isSugared: false) else { return }
        var names: [String] = []
        if throughModule, let canonical = recordedName(of: spelling, from: scope) { names.append(canonical) }
        if let recorded = recordedName(of: type.declaration), !names.contains(recorded) { names.append(recorded) }
        let rank = memberRank(adding: scope, to: type.scope)
        for name in names where name != spelling {
            for member in aliases {
                guard let alias = member.name else { continue }
                let ranked = LayoutGraphBuilder.Declared(
                    member, kind: .typealias, nodeId: nil, in: anExtension, rankedAs: rank
                )
                record(ranked, named: "\(name).\(alias)")
            }
        }
    }

    /// Records each typealias an extension merged into `item` declares under that extension's
    /// spelling, when it is not `item`'s own name.
    private mutating func recordMergedAliases(of item: SyntaxStructure, named containerName: String) {
        for merged in item.mergedExtensions {
            guard let spelling = merged.fullName ?? merged.name, spelling != containerName else { continue }
            for member in merged.substructure ?? [] where member.kind == .typealias {
                guard let name = member.name else { continue }
                record(mergedAlias(member, in: item, from: merged), named: "\(spelling).\(name)")
            }
        }
    }

    /// The typealias `member` of `container`, read in the extension it was merged in from,
    /// `home`, when there is one, and ranked by `memberRank`.
    private func mergedAlias(
        _ member: SyntaxStructure, in container: SyntaxStructure, from home: SyntaxStructure?
    ) -> LayoutGraphBuilder.Declared {
        let ranked = LayoutGraphBuilder.Declared(member, kind: .typealias, nodeId: nil, in: container)
        guard let home else { return ranked }
        let rank = memberRank(adding: LayoutGraphBuilder.Scope(of: home), to: ranked.rankScope)
        return LayoutGraphBuilder.Declared(member, kind: .typealias, nodeId: nil, in: home, rankedAs: rank)
    }

    /// The scope a member an extension in `adding` adds to a type in `type` ranks by: the type's,
    /// as a member of it, where a lookup of the type finds it, when the two share a module; else
    /// its own module's, in no file. A module cannot import one that depends on it, so ranked as
    /// the type, ModB's `Foo.X` would come first in ModA's own file, where ModA's own `Foo.X` is
    /// meant. With no module on either, the extension's own scope: the directory stands in for
    /// the module, and ranked in the type's file, every extension's `Foo.X` would be as near as
    /// any other to a writer elsewhere, so the first read would win, in another target (#230).
    private func memberRank(
        adding scope: LayoutGraphBuilder.Scope, to type: LayoutGraphBuilder.Scope
    ) -> LayoutGraphBuilder.Scope {
        guard scope.module != nil || type.module != nil else { return scope }
        guard let module = scope.module, let typeModule = type.module, module != typeModule else { return type }
        return LayoutGraphBuilder.Scope(filePath: nil, module: module)
    }

    /// The types nested in `container`, written `name`, that the lookup has not recorded, as
    /// while nested types are hidden, and their typealiases, all the way down, by full name.
    /// Whether an extension is of a project type goes by them too
    /// (`startsAtProjectType(_:from:depth:)`), so `extension Date.Box` after
    /// `extension Date { struct Box {} }` is the project's, and `extension Box.Inner.Stamp` after
    /// `struct Box { struct Inner { typealias Stamp = Date } }` is not, with nested types hidden.
    /// One an extension of another module merged into `container` ranks in that module
    /// (`memberRank`), as a typealias it adds does: in ModA, ModB's hidden `Foo.V` never
    /// outranks ModA's own `Foo.V` alias.
    private func unlistedMembers(
        of container: SyntaxStructure, named name: String
    ) -> [String: [LayoutGraphBuilder.Declared]] {
        var found: [String: [LayoutGraphBuilder.Declared]] = [:]
        let origins = container.mergedMemberOrigins
        for member in container.substructure ?? [] {
            guard let kind = member.kind, ElementKind.processable.contains(kind), kind != .extension,
                  kind != .macro, let memberName = member.name,
                  recordedName(of: ObjectIdentifier(member)) == nil else { continue }
            let fullName = "\(name).\(memberName)"
            let plain = LayoutGraphBuilder.Declared(member, kind: kind, nodeId: nil, in: container)
            let nested = origins[ObjectIdentifier(member)].map {
                let rank = memberRank(adding: LayoutGraphBuilder.Scope(of: $0), to: plain.rankScope)
                return LayoutGraphBuilder.Declared(member, kind: kind, nodeId: nil, in: container, rankedAs: rank)
            } ?? plain
            found[fullName, default: []].append(nested)
            for alias in member.substructure ?? [] where alias.kind == .typealias {
                guard let aliasName = alias.name else { continue }
                let declared = LayoutGraphBuilder.Declared(alias, kind: .typealias, nodeId: nil, in: member)
                found["\(fullName).\(aliasName)", default: []].append(declared)
            }
            found.merge(unlistedMembers(of: member, named: fullName)) { $0 + $1 }
        }
        return found
    }

    /// The name the type the extension `anExtension` extends comes to (`resolvedName(of:from:)`),
    /// so two extensions of one type outside the diagram share it however each spells the
    /// type. Written with sugar, it is the standard-library type's name as it stands (#126).
    /// `nil` when the name is not sure (`sureResolvedName(of:from:depth:)`): such an extension
    /// shares no box or edge end with another spelling.
    func resolvedExtendedName(of anExtension: SyntaxStructure) -> String? {
        guard let name = anExtension.fullName else { return nil }
        let scope = LayoutGraphBuilder.Scope(of: anExtension)
        return resolvedExtendedName(named: name, from: scope, isSugared: anExtension.isSugared)
    }

    /// `resolvedExtendedName(of:)` for an extension that writes its type as `name` in `scope`.
    func resolvedExtendedName(named name: String, from scope: LayoutGraphBuilder.Scope, isSugared: Bool) -> String? {
        guard !isSugared else { return name }
        return sureResolvedName(of: LayoutGraphBuilder.QualifiedName(name: name, root: .asWritten), from: scope)
    }
}
