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

    /// A name to look up, and which type it starts at. `isRecorded` marks one built on the name
    /// a type is recorded under rather than on one written in the source, `Analytics.Event` for
    /// Other's namespace in an extension spelled through a typealias of it: its first component
    /// is no module qualifier to read.
    struct QualifiedName {
        let name: String
        let root: NameRoot
        var isRecorded = false
        /// For a dotted name as written, the type its first component means, once worked out
        /// (`TypeLookup.started(_:from:depth:)`).
        var start: NameStart?
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
    /// enclosing type takes only those of that type's root, and with no module, where an
    /// extension adds one of them, only those of that very type (`membersOfEnclosingType`,
    /// #252). A bare name takes those the file
    /// sees (`seenAtFileScope(_:named:from:)`). A dotted name as written takes the members of the
    /// type its first component means there. Where that is worked out (`started(_:from:depth:)`),
    /// they are the members of that very type, an extension's if the writer's module loads it.
    /// Otherwise, as for sources read without their package or a first component read as a
    /// module, they are those of its root, the project's `Array` unless a nearer one shadows it,
    /// but only when the candidates are not all of one root: a name the diagram does not mix up
    /// keeps every candidate, as it always has, and costs no lookup. So are a started name's
    /// when that type has none, among those the file can reach
    /// (`fallbackCandidates(_:for:from:depth:)`). With no module, where an extension adds one of
    /// them, they are also that type's alone (`membersOfWrittenStart(_:named:from:depth:)`).
    func fitting(
        _ candidates: [LayoutGraphBuilder.Declared], for name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        switch name.root {
        case .projectType:
            // A name built on `extension Analytics.Event` reads its qualifier as the extension
            // does, so `Inner` in it is not one nested in a namespace the file does not import.
            let seen = name.isRecorded
                ? candidates : seenWhenQualifierIsModule(candidates, named: name.name, from: scope, depth: depth)
            let fitted = seen.filter { !isInExtensionOfOutsideType($0, depth: depth) }
            guard fitted.count > 1, fitted.contains(where: { $0.extended != nil }) else { return fitted }
            return membersOfEnclosingType(fitted, from: scope, depth: depth)
        case .outsideType:
            return candidates.filter { isInExtensionOfOutsideType($0, depth: depth) }
        case .asWritten:
            var candidates = seenWhenQualifierIsModule(candidates, named: name.name, from: scope, depth: depth)
            guard name.name.contains(".") else { return seenAtFileScope(candidates, named: name.name, from: scope) }
            if let start = name.start {
                if let members = members(of: start, among: candidates, from: scope, depth: depth) { return members }
                candidates = fallbackCandidates(candidates, for: name, from: scope, depth: depth)
            } else {
                // A first component read as a module, `ModA` in `ModA.Foo.V`, sets no start, but
                // the writer still sees only the extensions its module loads (#245).
                candidates = loaded(candidates, from: scope, depth: depth)
            }
            guard candidates.count > 1, candidates.contains(where: { $0.extended != nil }) else {
                return candidates
            }
            candidates = membersOfWrittenStart(candidates, named: name.name, from: scope, depth: depth)
            guard candidates.count > 1 else { return candidates }
            let isOutside = candidates.map { isInExtensionOfOutsideType($0, depth: depth) }
            guard isOutside.contains(true), isOutside.contains(false) else { return candidates }
            let startsOutside = firstComponentType(of: name.name, from: scope, depth: depth) == nil
            return zip(candidates, isOutside).filter { $0.1 == startsOutside }.map(\.0)
        }
    }

    /// In a file of no known module, where no start is worked out (`started(_:from:depth:)`), the
    /// `candidates` of the dotted `name` that belong to the type its first component means from
    /// `scope` (`members(ownedBy:among:from:depth:)`, #230).
    private func membersOfWrittenStart(
        _ candidates: [LayoutGraphBuilder.Declared], named name: String,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        guard scope.module == nil, depth < 8,
              let start = firstComponentType(of: name, from: scope, depth: depth),
              let owner = owningDeclaration(of: start, depth: depth) else { return candidates }
        return members(ownedBy: owner, among: candidates, from: scope, depth: depth)
    }

    /// In a file of no known module, the `candidates` of a name built on the types around `scope`
    /// that belong to the outermost of them (`members(ownedBy:among:from:depth:)`, #252): for
    /// `class W: X` in `extension Foo`, a member of the `Foo` that extension extends, and not one
    /// another extension near `W` adds to another target's `Foo`. That type is the one the
    /// outermost name means from the file, as an extension's own lookup finds it, which is also the
    /// type a member merged out of an extension sits in.
    private func membersOfEnclosingType(
        _ candidates: [LayoutGraphBuilder.Declared], from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        guard scope.module == nil, let owner = enclosingOwner(of: scope, depth: depth) else { return candidates }
        return members(ownedBy: owner, among: candidates, from: scope, depth: depth)
    }

    /// Whether `localNearest(_:from:depth:)` may answer a name built on the types around `scope`
    /// with `local`, the first candidate ranked in the writer's file, without the rest: when it
    /// belongs to the outermost of those types, or that type is unknown, `fitting` keeps it among
    /// all of them, and ranked in the writer's file, it comes first. Otherwise the others decide.
    func mayAnswerAlone(
        _ local: LayoutGraphBuilder.Declared, builtOnTypesAround scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        guard let owner = enclosingOwner(of: scope, depth: depth) else { return true }
        return owningDeclaration(of: local, depth: depth).map { $0 == owner } ?? false
    }

    /// `lookUp`'s candidates for `name` from `scope`, kept for a name built on the types around a
    /// writer of no known module that is fitted by what the whole set holds
    /// (`fitsEachAlone(_:from:)`). Those depend on the name, the writer's scope and the depth
    /// alone, and every writer in one extension of a file shares the scope, so each such scope
    /// scans the name's same-named types once rather than at each of its many lookups (#252). Any
    /// other name is looked up afresh, as before: its candidates cost no more.
    func enclosingCandidates(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int,
        lookUp: () -> [LayoutGraphBuilder.Declared]
    ) -> [LayoutGraphBuilder.Declared] {
        guard name.root == .projectType, scope.module == nil, !fitsEachAlone(name, from: scope) else { return lookUp() }
        return enclosingLookups.candidates(for: enclosingKey(name, from: scope, depth: depth), lookUp: lookUp)
    }

    /// `name` built on the types around `scope`, with all of the writer's scope that what it means
    /// there can depend on (`EnclosingCandidatesKey`).
    func enclosingKey(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.EnclosingCandidatesKey {
        LayoutGraphBuilder.EnclosingCandidatesKey(
            name: name.name, isRecorded: name.isRecorded, filePath: scope.filePath.map { Array($0.utf8) },
            imports: scope.imports,
            enclosingTypes: scope.enclosingTypes, enclosingExtension: scope.enclosingExtension?.name,
            isSugared: scope.enclosingExtension?.isSugared ?? false, depth: depth
        )
    }

    /// The outermost type around `scope`, by name and file (`owningDeclaration(of:depth:)`): the
    /// one the outermost name means from the file, as an extension's own lookup finds it.
    /// `nil` at top level, or when the name means no type of the diagram. Kept per name and file
    /// (`EnclosingLookups`), as each writer there asks it of every name it builds on them.
    func enclosingOwner(
        of scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.OwningDeclaration? {
        guard depth < 8, let outermost = scope.enclosingTypes.last else { return nil }
        let isSugared = scope.enclosingExtension?.isSugared ?? false
        let key = LayoutGraphBuilder.EnclosingOwnerKey(
            outermost: outermost, isSugared: isSugared, filePath: scope.filePath.map { Array($0.utf8) },
            imports: scope.imports, depth: depth
        )
        return enclosingLookups.owner(for: key) {
            extendedType(named: outermost, from: scope.fileScope, isSugared: isSugared, depth: depth + 1)
                .flatMap { owningDeclaration(of: $0, depth: depth) }
        }
    }

    /// The `candidates` that belong to the outermost type `owner`, or every candidate when none
    /// does. A member that type's body declares for every module to see then goes before an
    /// extension's in another directory: a file that sees both does not compile, so one that
    /// compiles means the body's. An `internal` one proves nothing, as another module cannot see
    /// it, and an extension in the writer's directory stays, since there the `Foo` both read may be
    /// another target's unrelated one, first read of those equally near.
    private func members(
        ownedBy owner: LayoutGraphBuilder.OwningDeclaration, among candidates: [LayoutGraphBuilder.Declared],
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        let members = candidates.filter { candidate in
            owningDeclaration(of: candidate, depth: depth).map { $0 == owner } ?? false
        }
        guard !members.isEmpty else { return candidates }
        let isPublicBodyMember = { (member: LayoutGraphBuilder.Declared) in
            member.extended == nil && member.ownAccess >= .package
        }
        guard members.contains(where: isPublicBodyMember), let writer = scope.rankingDirectory else { return members }
        return members.filter { isPublicBodyMember($0) || $0.scope.rankingDirectory == writer }
    }

    /// The outermost type `declared` belongs to past any extension, by name and file, which tell
    /// same-named types apart where they have no module; `nil` for one in an extension of a type
    /// outside the diagram.
    func owningDeclaration(
        of declared: LayoutGraphBuilder.Declared, depth: Int
    ) -> LayoutGraphBuilder.OwningDeclaration? {
        guard declared.extended != nil else { return (declared.outermostName, declared.outermostFilePath) }
        guard depth < 8, let type = enclosingExtensionType(of: declared, depth: depth) else { return nil }
        return owningDeclaration(of: type, depth: depth + 1)
    }
}
