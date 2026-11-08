import Foundation

// MARK: - Members of the Type Around a Writer

/// Whether a name built on the types around a writer, `Foo.X` for `class W: X` in
/// `extension Foo`, means a member of that very type, kept apart from `TypeLookup` so its file
/// stays a readable size (#252).
extension LayoutGraphBuilder.TypeLookup {
    typealias OwningDeclaration = LayoutGraphBuilder.OwningDeclaration

    /// Whether `name`, built on the types around `scope`, means a member of them there: `nil` when
    /// it means no declaration, and otherwise whether the one it means lets it
    /// (`isMemberOfTypeAround(_:named:from:depth:readingModules:)`).
    func meansMember(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: Scope, depth: Int, readingModules: Bool
    ) -> Bool? {
        nearestDeclaration(name, from: scope, depth: depth, readingModules: readingModules).map {
            isMemberOfTypeAround($0, named: name, from: scope, depth: depth, readingModules: readingModules)
        }
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
    /// tell, as in an extension of a type outside the diagram.
    func isMemberOfTypeAround(
        _ found: Declared, named name: LayoutGraphBuilder.QualifiedName, from scope: Scope, depth: Int,
        readingModules: Bool
    ) -> Bool {
        guard scope.module != nil, let owner = enclosingOwner(of: scope, depth: depth) else { return true }
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

    /// Whether the last part of the dotted `name` is inherited through a type that may be the
    /// writer's own (`isOwn`): the type the part before the last dot means from `scope`, as
    /// `inheritedLookup` reads it, or, when that is itself inherited, as `Inner` in `Sub.Inner.Leaf`
    /// from `class Base { class Inner }`, the type it is inherited through, `Sub`, and so on out.
    private func inheritsThroughOwnType(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: Scope, depth: Int, readingModules: Bool,
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
