// MARK: - Members of the Type Around a Writer

/// Whether a name built on the types around a writer, `Foo.X` for `class W: X` in
/// `extension Foo`, means a member of that very type, kept apart from `TypeLookup` so its file
/// stays a readable size (#252).
extension LayoutGraphBuilder.TypeLookup {
    typealias OwningDeclaration = LayoutGraphBuilder.OwningDeclaration

    /// What a name built on the types around a writer means there (`meansMember`).
    enum MemberMeaning { case noDeclaration, member, notMember }

    /// Whether `name`, built on the types around `scope`, means a member of them there:
    /// `.noDeclaration` when it means no declaration, and otherwise whether the one it means lets
    /// it (`isMemberOfTypeAround(_:named:from:depth:readingModules:)`).
    func meansMember(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: Scope, depth: Int, readingModules: Bool
    ) -> MemberMeaning {
        guard let found = nearestDeclaration(name, from: scope, depth: depth, readingModules: readingModules) else {
            return .noDeclaration
        }
        let isMember = isMemberOfTypeAround(
            found, named: name, from: scope, depth: depth, readingModules: readingModules
        )
        return isMember ? .member : .notMember
    }

    /// The type a name `qualifiedName(ofWritten:from:depth:readingModules:)` builds on the
    /// outermost type around `scope`, or on the type its extension is spelled through, starts at,
    /// as the dotted name spelling it out starts there (`started(_:from:depth:)`): that type,
    /// ModA's `Foo` both in `extension Foo` and in `extension ModA.Foo` of a file that means
    /// ModA's, as the extension's own lookup finds it. Swift looks the bare `V` in such an
    /// extension up among that type's members, which `spellings(of:)` finds however another
    /// module's extension spells the type, and only among those the writer sees: an extension's
    /// in a module the writer's module loads, or with `MemberImportVisibility`, one its file
    /// imports (`members(of:among:from:depth:)`). A name built on a type nested in it gets no
    /// start: `Foo.S.V` in `extension Foo { struct S { … } }` means a member of the writer's own
    /// `S`, not of every `Foo.S` another module adds. `nil` in a file of no known module, where
    /// same-named types are told apart by directory instead (`membersOfEnclosingType`), and at
    /// top level. Kept per outermost name and file (`EnclosingLookups`), as each writer there
    /// asks it of every name it builds on them.
    func enclosingStart(of scope: Scope, depth: Int) -> LayoutGraphBuilder.NameStart? {
        guard scope.module != nil, depth < 8, let outermost = scope.enclosingTypes.last else { return nil }
        let isSugared = scope.enclosingExtension?.isSugared ?? false
        let key = LayoutGraphBuilder.EnclosingOwnerKey(
            outermost: outermost, isSugared: isSugared, filePath: scope.filePath.map { Array($0.utf8) },
            imports: scope.imports, depth: depth
        )
        return enclosingLookups.start(for: key) {
            extendedType(named: outermost, from: scope.fileScope, isSugared: isSugared, depth: depth + 1)
                .map { .projectType(owningType(of: $0, depth: depth), renamedTo: nil) }
        }
    }

    /// Whether `name`, built on the types around a writer in `scope`, may mean a member only once
    /// it starts there (`enclosingStart(of:depth:)`): a member `extension ModA.Foo` adds is recorded
    /// under `ModA.Foo.V`, which the started `Foo.V` spells (`spellings(of:)`). A name is started
    /// only in a file of a known module. A dictionary check, before any lookup.
    func mayBeStartedMember(_ name: String, from scope: Scope) -> Bool {
        scope.module != nil && namesPastFirstComponent.contains(name)
    }

    /// Whether `found`, the declaration `name` means from `scope`, lets a name built on the types
    /// around `scope` mean it. With the writer's module known, it does not when neither it nor any
    /// other candidate of the name belongs to the outermost of those types (`enclosingOwner`) where
    /// the writer's module loads it, as for `class W: X` in `extension Foo` when only another
    /// module's `Foo` has an `X`, or one a module downstream of the writer's adds: Swift then finds
    /// no such member and reads `X` further out. Which type that is the lookup knows for sure only
    /// as Swift's rules settle it (`ownerIsSettled`); otherwise a member of a type named like it
    /// that the writer's file sees may be its own (`mayBeTypeAround`). A member a superclass
    /// declares is the type's own when it is inherited through a type that is
    /// (`inheritsThroughOwnType`), even from a superclass named like it (`class Foo: Core.Foo`).
    /// With no module known, which same-named `Foo` a file means is a guess by directory, which a
    /// target sharing a directory, a file an Xcode project compiles into several targets, or one a
    /// package excludes all defeat, so the name stands as before; it does too with no owner to
    /// tell, as in an extension of a type outside the diagram. Every writer in one extension of a
    /// file finds the same declaration, so the answer is kept for them all (`EnclosingLookups`).
    func isMemberOfTypeAround(
        _ found: Declared,
        named name: LayoutGraphBuilder.QualifiedName,
        from scope: Scope,
        depth: Int,
        readingModules: Bool
    ) -> Bool {
        guard scope.module != nil, let owner = enclosingOwner(of: scope, depth: depth) else { return true }
        let key = LayoutGraphBuilder.EnclosingMemberKey(
            place: enclosingKey(name, from: scope, depth: depth), found: found.declaration,
            readingModules: readingModules
        )
        return enclosingLookups.isMember(for: key) {
            let isSettled = ownerIsSettled(from: scope, depth: depth)
            let isOwn = { (declared: Declared) in
                self.belongs(declared, to: owner, from: scope, depth: depth)
                    || !isSettled && self.mayBeTypeAround(declared, named: owner.name, from: scope, depth: depth)
            }
            if isOwn(found) { return true }
            if case .member(let inherited)? = inheritedLookup(
                name, from: scope, depth: depth, readingModules: readingModules
            ), inherited.declaration == found.declaration, inheritsThroughOwnType(
                name, from: scope, depth: depth, readingModules: readingModules, isOwn: isOwn
            ) {
                return true
            }
            return candidates(name, from: scope, depth: depth).contains(where: isOwn)
        }
    }

    /// Whether the last part of the dotted `name` is inherited through a type that may be the
    /// writer's own (`isOwn`): the type the part before the last dot means from `scope`, as
    /// `inheritedLookup` reads it, or, when that is itself inherited, as `Inner` in `Sub.Inner.Leaf`
    /// from `class Base { class Inner }`, the type it is inherited through, `Sub`, and so on out.
    private func inheritsThroughOwnType(
        _ name: LayoutGraphBuilder.QualifiedName,
        from scope: Scope,
        depth: Int,
        readingModules: Bool,
        isOwn: (Declared) -> Bool
    ) -> Bool {
        var (prefix, level) = (name, depth)
        while level < 8, let dot = prefix.name.lastIndex(of: ".") {
            let container = LayoutGraphBuilder.QualifiedName(
                name: String(prefix.name[..<dot]), root: prefix.root, isRecorded: prefix.isRecorded
            )
            guard let type = type(container, from: scope, depth: level + 1, readingModules: readingModules) else {
                return true
            }
            if isOwn(type) { return true }
            guard case .member? = inheritedLookup(
                container, from: scope, depth: level + 1, readingModules: readingModules
            ) else { return false }
            (prefix, level) = (container, level + 1)
        }
        return false
    }

    /// Whether `declared` belongs to `owner`, the outermost type around `scope`, where the writer's
    /// module loads it (`loaded`): not when only a module downstream of the writer's adds it. One of
    /// unknown owner may belong.
    private func belongs(_ declared: Declared, to owner: OwningDeclaration, from scope: Scope, depth: Int) -> Bool {
        guard let declaredOwner = owningDeclaration(of: declared, depth: depth) else { return true }
        return declaredOwner == owner && !loaded([declared], from: scope, depth: depth).isEmpty
    }

    /// Whether Swift's rules settle which type the outermost name around `scope` means, as the
    /// lookup finds it: one of the writer's own module, which shadows every import, or one the
    /// file imports alone (`import struct Core.Foo`). Otherwise the lookup may take another of that
    /// name for it, as Core's `Foo` beside Umbrella's own, which Umbrella's `@_exported import Core`
    /// shows too, and which Swift takes.
    private func ownerIsSettled(from scope: Scope, depth: Int) -> Bool {
        guard let outermost = scope.enclosingTypes.last,
              let type = extendedType(
                  named: outermost, from: scope.fileScope,
                  isSugared: scope.enclosingExtension?.isSugared ?? false, depth: depth + 1
              ),
              let owning = owningType(of: type, depth: depth), let module = owning.module else { return false }
        return module == scope.module || owning.name.map { seesAlone($0, in: module, from: scope) } == true
    }

    /// Whether `declared` belongs to a type named `name`, as the outermost type around `scope` is,
    /// that the writer's file sees, where the writer's module loads it: one Swift may take for the
    /// type around the writer where the lookup's own reading of it is not settled.
    private func mayBeTypeAround(_ declared: Declared, named name: String?, from scope: Scope, depth: Int) -> Bool {
        guard let owning = owningType(of: declared, depth: depth), let module = owning.module,
              let typeName = owning.name, typeName == name else { return false }
        return sees(typeName, in: module, from: scope) && !loaded([declared], from: scope, depth: depth).isEmpty
    }
}
