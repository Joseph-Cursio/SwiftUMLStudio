import Foundation

// MARK: - Name Roots

/// Which type a dotted name starts at, kept apart from `TypeLookup` so its file stays a readable
/// size. A type nested in an extension is recorded under the extended type's name, so `Array.Base`
/// is both a `Base` nested in a project `struct Array` and one declared in `extension [Int]`, a
/// member of Swift's `Array` (#126). Which of them the name means depends on what its first
/// component means where it is written.
extension LayoutGraphBuilder {
    /// What a dotted name's first component is, which decides which of the declarations recorded
    /// under the name it can mean (`TypeLookup.fitting(_:for:from:depth:)`).
    enum NameRoot {
        /// Whatever the first component means where the name is written: a type the project
        /// declares there, or else a type outside the diagram, such as Swift's `Array`.
        case asWritten
        /// A type the project declares: the name means a member of it, or of an extension of it.
        case projectType
        /// A type outside the diagram: the name means a member the project declares in an
        /// extension of it, as `extension [Int] { class Base {} }` declares one of Swift's `Array`.
        case outsideType
    }

    /// A name to look up, and which type it starts at.
    struct QualifiedName {
        let name: String
        let root: NameRoot
    }
}

// An extension of `TypeLookup` in another file does not see the builder's own names, so they are
// written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// The type the extension `anExtension` extends
    /// (`extendedType(named:from:isSugared:depth:)`), as seen from where it is written.
    func extendedType(of anExtension: SyntaxStructure) -> LayoutGraphBuilder.Declared? {
        guard let name = anExtension.fullName else { return nil }
        let scope = LayoutGraphBuilder.Scope(of: anExtension)
        return extendedType(named: name, from: scope, isSugared: anExtension.isSugared)
    }

    /// The type an extension that writes its type as `name` in `scope` extends: the one the
    /// name means there (`type(named:from:depth:)`), or `nil` for a type outside the diagram.
    /// Sugar (`isSugared`) always means the standard library's type: `[Int]`, `[String: Int]`
    /// and `Int?` are Swift's `Array`, `Dictionary` and `Optional`, outside the diagram even
    /// beside a project's own type of that name, which a bare `Array` would mean (#126). A
    /// member path past the sugar, `Array.Stats` for `[Int].Stats`, names a member the project
    /// may declare in an extension of that type (`NameRoot.outsideType`), and never one nested
    /// in a project `struct Array`; `nil` when there is none, as for Swift's own `[Int].Index`.
    /// `mergeExtensions`, the `ext` edge, the edges of the types nested in an extension, its
    /// stand-ins and the access cap on those nested types all ask this, so they agree.
    func extendedType(
        named name: String, from scope: LayoutGraphBuilder.Scope, isSugared: Bool, depth: Int = 0
    ) -> LayoutGraphBuilder.Declared? {
        guard isSugared else { return type(named: name, from: scope, depth: depth) }
        // The sugared base is one name, `Array`; a member is joined on with a `.`.
        guard name.contains(".") else { return nil }
        return type(LayoutGraphBuilder.QualifiedName(name: name, root: .outsideType), from: scope, depth: depth)
    }

    /// Whether `declared` is declared in an extension of a type outside the diagram, or in an
    /// extension of a member the project declares in one, however deep: `Stats` in
    /// `extension [Int]`, and `Bucket` in `extension [Int].Stats`.
    func isInExtensionOfOutsideType(_ declared: LayoutGraphBuilder.Declared, depth: Int) -> Bool {
        guard declared.extended != nil, depth < 8 else { return false }
        guard let type = enclosingExtensionType(of: declared, depth: depth) else { return true }
        return isInExtensionOfOutsideType(type, depth: depth + 1)
    }

    /// Whether the extension that writes its type as `target` extends a type outside the
    /// diagram, or a member the project declares in an extension of one.
    private func extendsOutsideType(_ target: LayoutGraphBuilder.ExtensionTarget, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        guard let type = extendedType(
            named: target.name, from: target.scope, isSugared: target.isSugared, depth: depth + 1
        ) else { return true }
        return isInExtensionOfOutsideType(type, depth: depth + 1)
    }

    /// The type the names `qualifiedName(ofWritten:from:)` builds on `scope`'s enclosing types
    /// start at: a type outside the diagram when they end at an extension of one,
    /// `extension [Int]` say, and otherwise a type the project declares. Inside the extension,
    /// Swift looks a name up among the members of the type it extends.
    func enclosingRoot(of scope: LayoutGraphBuilder.Scope, depth: Int) -> LayoutGraphBuilder.NameRoot {
        guard let enclosing = scope.enclosingExtension else { return .projectType }
        // An extension's own clause sees no enclosing types.
        let target = LayoutGraphBuilder.ExtensionTarget(
            name: enclosing.name, scope: scope.fileScope, isSugared: enclosing.isSugared
        )
        return extendsOutsideType(target, depth: depth) ? .outsideType : .projectType
    }

    /// The `candidates` recorded under `name` that it can mean from `scope`. A name built on an
    /// enclosing type takes only those of that type's root. A dotted name as written takes those
    /// of the type its first component means there, the project's `Array` unless a nearer one
    /// shadows it, but only when the candidates are not all of one root: a name the diagram does
    /// not mix up keeps every candidate, as it always has, and costs no lookup of its root.
    func fitting(
        _ candidates: [LayoutGraphBuilder.Declared], for name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        switch name.root {
        case .projectType:
            return candidates.filter { !isInExtensionOfOutsideType($0, depth: depth) }
        case .outsideType:
            return candidates.filter { isInExtensionOfOutsideType($0, depth: depth) }
        case .asWritten:
            guard candidates.count > 1, let dot = name.name.firstIndex(of: "."),
                  candidates.contains(where: { $0.extended != nil }) else {
                return candidates
            }
            let isOutside = candidates.map { isInExtensionOfOutsideType($0, depth: depth) }
            guard isOutside.contains(true), isOutside.contains(false) else { return candidates }
            // Swift looks the first component up as a bare name, a member of the types around it
            // first, so `typealias Array = [Int]` in an enclosing type counts.
            let first = qualifiedName(ofWritten: String(name.name[..<dot]), from: scope, depth: depth + 1)
            let startsOutside = type(first, from: scope, depth: depth + 1) == nil
            return zip(candidates, isOutside).filter { $0.1 == startsOutside }.map(\.0)
        }
    }
}
