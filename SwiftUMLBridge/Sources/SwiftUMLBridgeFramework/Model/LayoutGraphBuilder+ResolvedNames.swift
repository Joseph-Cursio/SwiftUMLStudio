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
    /// takes it everywhere else, so `Describable` written there is the project's typealias.
    func sureResolvedName(
        of name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int = 0
    ) -> String? {
        guard depth < 8 else { return name.name }
        let match = nearestMatch(name, from: scope, depth: depth)
        if match == nil, name.root == .asWritten, mayMeanOutsideMember(from: scope, depth: depth) {
            return nil
        }
        guard let match else { return name.name }
        guard let target = match.declared.aliasTarget else { return match.name }
        guard !match.declared.isSugared else { return target }
        let targetName = qualifiedName(ofWritten: target, from: match.declared.scope, depth: depth + 1)
        return sureResolvedName(of: targetName, from: match.declared.scope, depth: depth + 1)
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
    /// lookup a part for each alias on the way, and the depth guard ends a cycle of them.
    private func startsAtProjectType(_ name: String, from scope: LayoutGraphBuilder.Scope, depth: Int) -> Bool {
        var parts = name.split(separator: ".").map(String.init)
        if parts.count > 1, parts[0] == scope.module,
           nearestVisible(named: parts[0], from: scope, depth: depth) == nil {
            parts.removeFirst()
        }
        if type(named: parts.joined(separator: "."), from: scope, depth: depth) != nil { return true }
        var prefix = ""
        var deciding: LayoutGraphBuilder.Declared?
        var used = 0
        for (index, part) in parts.enumerated() {
            prefix = prefix.isEmpty ? part : "\(prefix).\(part)"
            guard let nearest = nearestVisible(named: prefix, from: scope, depth: depth)
                ?? unlistedMembers[prefix]?.first(where: { isVisible($0, from: scope, depth: depth) })
            else { continue }
            deciding = nearest
            used = index + 1
        }
        guard let deciding else { return false }
        guard let target = deciding.aliasTarget else { return true }
        guard !deciding.isSugared, depth < 8 else { return false }
        // The parts after the deciding alias are members of what it stands for.
        let tail = Array(parts.dropFirst(used))
        // A target nested beside the alias that the lookup does not record, as while nested types
        // are hidden, is one of the unlisted members of the alias's container or of a type around
        // it: `Stamp = Real` in `Box.Inner` is `Box.Inner.Real`.
        if let unlisted = unlistedTarget(target, around: Array(parts.prefix(used - 1))),
           startsAtProjectType(([unlisted] + tail).joined(separator: "."), from: deciding.scope, depth: depth + 1) {
            return true
        }
        let written = qualifiedName(ofWritten: target, from: deciding.scope, depth: depth + 1)
        let rest = ([written.name] + tail).joined(separator: ".")
        return startsAtProjectType(rest, from: deciding.scope, depth: depth + 1)
    }

    /// Whether a nested type the items do not list (`unlistedMembers`), as while nested types are
    /// hidden, is what `name` means from `scope` rather than `nearest`: it ranks nearer, as it
    /// would were it recorded, a type before a typealias among equals, as recording types first
    /// makes it. Such a name finds no end, as one with no candidate does: in ModB, `Foo.V` is
    /// ModB's own hidden `struct Foo { class V {} }`, never `typealias V = Base` in ModB's
    /// `extension ModA.Foo`, which the lookup also records as `Foo.V`.
    func unlistedMemberShadows(
        _ nearest: LayoutGraphBuilder.Declared, named name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        guard name.root != .outsideType, let unlisted = unlistedMembers[name.name] else { return false }
        let visible = unlisted.filter {
            $0.declaration != nearest.declaration && isVisible($0, from: scope, depth: depth)
        }
        let rivals = fitting(visible, for: name, from: scope, depth: depth)
        guard !rivals.isEmpty else { return false }
        let ranked = nearest.aliasTarget == nil ? [nearest] + rivals : rivals + [nearest]
        return scope.nearest(among: ranked, scope: \.rankScope)?.declaration != nearest.declaration
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

    /// Records the typealiases among `items` and among their members, a member as
    /// `Container.Alias`, so a name written through one means the type it aliases (#125). Run
    /// after the types are recorded: when nothing else tells two candidates apart, `nearest`
    /// picks the first, and that should be a type. A typealias that an extension merged into
    /// its container declares (`SyntaxStructure.mergedExtensions`) is read where that extension
    /// declares it, as when the extensions are drawn apart, but ranks as a member of its
    /// container, where a lookup of the container finds it: moved into ModA's `Foo` from ModB's
    /// `extension ModA.Foo`, it ranks as ModA's, so ModB's own `Foo.Alias` still comes first in
    /// ModB. It is recorded under the extension's own spelling too: `extension Crate { typealias
    /// Desc }` merged into `struct Outer` makes both `Outer.Desc` and `Crate.Desc`. The nested
    /// types the items do not list are kept apart (`unlistedMembers`).
    mutating func recordAliases(in items: [SyntaxStructure]) {
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
            unlistedMembers.merge(unlistedMembers(of: item, named: containerName)) { $0 + $1 }
        }
        for item in items where item.kind == .extension { recordAliasSpelledMembers(of: item) }
    }

    /// Records each typealias an extension declares under the name of the type it extends too,
    /// when it spells that type through a typealias or a module, as merging it does
    /// (`recordMergedAliases`), ranked as a member of that type, where a lookup of the type
    /// finds it: after `extension Crate { typealias D = Date }`, `Outer.D` is `Date` drawn apart
    /// as well, and an alias in `extension ModA.Foo` is also `Foo.Alias`. Spelled through a
    /// module, it is also recorded under the name the declaration the spelling means is recorded
    /// under, before any typealias is followed: `FA.Alias` in `extension ModA.FA`.
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
    /// `home`, when there is one, and ranked as a member of `container` (`memberRank`).
    private func mergedAlias(
        _ member: SyntaxStructure, in container: SyntaxStructure, from home: SyntaxStructure?
    ) -> LayoutGraphBuilder.Declared {
        let ranked = LayoutGraphBuilder.Declared(member, kind: .typealias, nodeId: nil, in: container)
        guard let home else { return ranked }
        let rank = memberRank(adding: LayoutGraphBuilder.Scope(of: home), to: ranked.rankScope)
        return LayoutGraphBuilder.Declared(member, kind: .typealias, nodeId: nil, in: home, rankedAs: rank)
    }

    /// The scope a typealias an extension in `adding` adds to a type in `type` ranks by: the
    /// type's, as a member of it, where a lookup of the type finds it, when the two share a
    /// module; else its own module's, in no file. A module cannot import one that depends on it,
    /// so ranked as the type, ModB's `Foo.X` would come first in ModA's own file, where ModA's
    /// own `Foo.X` is meant.
    private func memberRank(
        adding scope: LayoutGraphBuilder.Scope, to type: LayoutGraphBuilder.Scope
    ) -> LayoutGraphBuilder.Scope {
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
