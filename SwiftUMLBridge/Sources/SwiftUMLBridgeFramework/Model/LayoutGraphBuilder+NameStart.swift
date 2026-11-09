import Foundation

// MARK: - Name Starts

/// Which type a dotted name as written starts at, read through the writer file's imports, kept
/// apart from `NameRoot` so each file stays a readable size. Swift resolves a dotted name's first
/// component as a bare name, among the types around it, its own module's and those of the modules
/// its file imports, then looks the rest up among the members of the type it means: those its body
/// declares and those extensions add.
extension LayoutGraphBuilder {
    /// The type a dotted name as written starts at, in a file of a known module whose imports are
    /// known (`TypeLookup.started(_:from:depth:)`).
    enum NameStart: Hashable {
        /// A type the project declares, which belongs to the outermost type `owner`, `nil` when
        /// that is unknown, as for a type in an extension of a type outside the diagram.
        /// `renamedTo` is the name that type is recorded under when the first component is
        /// another name for it, as `typealias Foo = ModA.Bar` makes `Foo` of `Bar`, and
        /// `typealias API = Networking.API` `API` of `Networking.API`: its members are
        /// recorded under that name.
        case projectType(OwningType?, renamedTo: String?)
        /// A type outside the diagram, such as Swift's `Array`. `spelledAs` is the name it is
        /// spelled by when the first component is another name for it, as
        /// `typealias Array = Date` makes `Array` of Foundation's `Date`, and
        /// `typealias Arr = [Int]` `Arr` of Swift's `Array`: an extension of it records its
        /// members under that name (#247).
        case outsideType(spelledAs: String?)
    }

    /// The outermost type a declaration belongs to past any extension, by its module and name
    /// (`TypeLookup.owningType(of:depth:)`): ModA's `Foo` both for the `V` that ModA's
    /// `struct Foo` declares and for one that ModB's `extension ModA.Foo` adds.
    struct OwningType: Hashable {
        let module: String?
        let name: String?
    }
}

// An extension of `TypeLookup` in another file does not see the builder's own names, so they are
// written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// `name` with the type its first component means worked out (`QualifiedName.start`), when
    /// it is a dotted name as written in a file whose module and imports are known, and its first
    /// component is read as a type: no module of the diagram has its name, the file cannot write
    /// that module (`canName`), or a type the file sees shadows it (`shadows`), as in
    /// `seenWhenQualifierIsModule`. Then a candidate is what the name means only as a member of
    /// that type (`members(of:among:from:depth:)`), whichever modules the other candidates are of.
    func started(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.QualifiedName {
        guard name.root == .asWritten, name.start == nil, scope.module != nil, scope.imports != nil,
              let dot = name.name.firstIndex(of: ".") else { return name }
        let first = String(name.name[..<dot])
        let named = modules.modules(namedBy: first)
        guard named.isEmpty || !canName(first, modules: named, from: scope)
            || shadows(first, from: scope, depth: depth) else {
            return name
        }
        var started = name
        started.start = start(of: first, in: name.name, from: scope, depth: depth)
        return started
    }

    /// The type the first component `first` of the dotted name `name` means where `scope`
    /// writes it, shared among the writers of one module and imports (`NameStarts`) when it
    /// can depend on nothing else: one at file scope whose own file declares no `first`.
    private func start(
        of first: String, in name: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.NameStart {
        func lookUp() -> LayoutGraphBuilder.NameStart {
            guard let type = firstComponentType(of: name, from: scope, depth: depth) else {
                return .outsideType(spelledAs: outsideSpelling(of: first, from: scope, depth: depth))
            }
            let recorded = recordedName(of: type.declaration)
            return .projectType(owningType(of: type, depth: depth + 1), renamedTo: recorded == first ? nil : recorded)
        }
        guard scope.enclosingTypes.isEmpty, scope.enclosingExtension == nil, let filePath = scope.filePath,
              typesForNameInFile[first]?[filePath] == nil else { return lookUp() }
        let key = LayoutGraphBuilder.NameStartKey(
            first: first, module: scope.module, imports: scope.imports, depth: depth
        )
        return nameStarts.start(for: key, lookUp: lookUp)
    }

    /// The type the first component of the dotted name `name` means where `scope` writes it, or
    /// `nil` for one outside the diagram. Swift looks it up as a bare name, a member of the types
    /// around it first, so `typealias Array = [Int]` in an enclosing type counts, and the writer
    /// module's own typealias of another module's type does too.
    func firstComponentType(
        of name: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.Declared? {
        let first = qualifiedName(ofWritten: String(name.prefix { $0 != "." }), from: scope, depth: depth + 1)
        return type(first, from: scope, depth: depth + 1)
    }

    /// The name of the type outside the diagram that the first component `first`, written in
    /// `scope`, is another name for, once every typealias on the way is followed
    /// (`resolvedName(of:from:readingModules:depth:)`): `Date` for `Array` after
    /// `typealias Array = Date`, and `Array` for `Arr` after `typealias Arr = [Int]`. `nil` when
    /// `first` is that type's own name.
    private func outsideSpelling(of first: String, from scope: LayoutGraphBuilder.Scope, depth: Int) -> String? {
        let written = qualifiedName(ofWritten: first, from: scope, depth: depth + 1)
        let spelled = resolvedName(of: written, from: scope, depth: depth + 1)
        return spelled == first ? nil : spelled
    }

    /// The `candidates` that are members of the type a dotted name starts at (`starts(_:at:depth:)`),
    /// an extension's only if the writer's module loads it (`loaded(_:from:depth:)`); `nil` when
    /// none of a project type's is left. Swift code that builds names a member of the type, so
    /// then the start, or the type a member belongs to, was misread, as when the file sees a
    /// type of that name in each of two modules and Swift takes the one a re-export or an
    /// `@available` attribute shadows, or a typealias on the way, or one an extension is spelled
    /// through, hides it, and the name is fitted as without a start
    /// (`fallbackCandidates(_:for:from:depth:)`).
    func members(
        of start: LayoutGraphBuilder.NameStart, among candidates: [LayoutGraphBuilder.Declared],
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared]? {
        let members = loaded(candidates.filter { starts($0, at: start, depth: depth) }, from: scope, depth: depth)
        if case .outsideType = start { return members }
        guard !members.isEmpty else { return nil }
        return members
    }

    /// The `candidates` a dotted name with a start but none of its members is fitted among, as
    /// without a start: those recorded under the name as written, the only ones read before
    /// starts were, of a type of a module the file sees, and, an extension's, loaded. The members
    /// gathered under the start's other spellings (`spellings(of:)`) are its members or nothing,
    /// so after `typealias Foo = ModA.Bar`, `Foo.V` never falls to another target's `Bar.V`.
    func fallbackCandidates(
        _ candidates: [LayoutGraphBuilder.Declared], for name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        let written = Set(((typesForName[name.name] ?? []) + (unlistedMembers[name.name] ?? [])).map(\.declaration))
        let seen = candidates.filter { candidate in
            guard written.contains(candidate.declaration) else { return false }
            guard let owner = owningType(of: candidate, depth: depth), let module = owner.module,
                  let ownerName = owner.name else { return true }
            return sees(ownerName, in: module, from: scope)
        }
        return loaded(seen, from: scope, depth: depth)
    }

    /// Whether `candidate` is a member of the type a dotted name starts at: of a type outside the
    /// diagram, declared in an extension of one; of a project type, of no such extension, and of
    /// the same outermost type (`owningType(of:depth:)`), by module and name, when both modules
    /// are known. So in a file that imports ModA alone, `Foo.V` is never the `V` of ModB's own
    /// `Foo`, and after the writer module's `typealias Foo = ModA.Bar`, only `Bar`'s; two
    /// declarations of one type, each under its own `#if`, are both that type.
    private func starts(
        _ candidate: LayoutGraphBuilder.Declared, at start: LayoutGraphBuilder.NameStart, depth: Int
    ) -> Bool {
        let isOutside = isInExtensionOfOutsideType(candidate, depth: depth)
        guard case .projectType(let owner, _) = start else { return isOutside }
        guard !isOutside else { return false }
        guard let owner, owner.module != nil, let owning = owningType(of: candidate, depth: depth),
              owning.module != nil else { return true }
        return owning == owner
    }

    /// The `candidates` of the bare `name` that a file in `scope` sees: those of its own module,
    /// and of the modules it imports, all of one or `name` alone, directly or through a
    /// re-export (`sees(_:in:from:)`). Swift reads no other module's top-level type, so with none
    /// of them left the name is a type outside the diagram, such as Foundation's `NSObject`. A
    /// scoped import, `import class ModB.Base`, shadows the `Base` of a module imported whole,
    /// so of other modules' candidates, those it names are kept alone.
    func seenAtFileScope(
        _ candidates: [LayoutGraphBuilder.Declared], named name: String, from scope: LayoutGraphBuilder.Scope
    ) -> [LayoutGraphBuilder.Declared] {
        let seen = candidates.filter { candidate in
            candidate.scope.module.map { sees(name, in: $0, from: scope) } ?? true
        }
        guard seen.count > 1 else { return seen }
        // Whether a scoped import names an imported candidate; `nil` for one of the file's own
        // module or of no known module, which ranks as before.
        func isScoped(_ candidate: LayoutGraphBuilder.Declared) -> Bool? {
            guard let module = candidate.scope.module, module != scope.module else { return nil }
            return seesAlone(name, in: module, from: scope)
        }
        let unscoped = seen.contains { isScoped($0) == true } ? seen.filter { isScoped($0) != false } : seen
        let opened = withoutUnopenedSPI(unscoped, from: scope)
        return availableOverUnavailable(unshadowedByReexport(opened, named: name, from: scope), from: scope)
    }

    /// `candidates` without those of other modules marked `@_spi`, when the file imports nothing
    /// with `@_spi` and another candidate remains: Swift shows such a type only to a file that
    /// imports its module with `@_spi`, so one an `@_spi` re-exporter declares does not shadow
    /// the type it re-exports (#200). A file that imports anything with `@_spi` keeps them all, as
    /// it cannot be told which module's group that import opens.
    private func withoutUnopenedSPI(
        _ candidates: [LayoutGraphBuilder.Declared], from scope: LayoutGraphBuilder.Scope
    ) -> [LayoutGraphBuilder.Declared] {
        guard scope.imports?.contains(ImportExtractor.spiImport) != true else { return candidates }
        func isUnopened(_ candidate: LayoutGraphBuilder.Declared) -> Bool {
            candidate.isSPI && candidate.scope.module.map { $0 != scope.module } == true
        }
        guard candidates.contains(where: isUnopened), candidates.contains(where: { !isUnopened($0) }) else {
            return candidates
        }
        return candidates.filter { !isUnopened($0) }
    }

    /// `candidates` without the unavailable ones (`Declared.isUnavailable`) of other modules, when
    /// one of another module is available: Swift lets an available type shadow an unavailable one,
    /// such as a stub `@available(*, unavailable, renamed: "NewBase")` leaves behind (#200). It
    /// runs last, as the writer's own module and a scoped import each shadow first, unavailable or
    /// not, so a candidate of the writer's module or of no known module stays. A
    /// candidate unavailable on one platform alone counts too: where it is available the name is
    /// ambiguous, and the file builds only where the available one is meant. Swift reads no
    /// availability in a member's lookup, `Foo.X`, so it does not run there.
    private func availableOverUnavailable(
        _ candidates: [LayoutGraphBuilder.Declared], from scope: LayoutGraphBuilder.Scope
    ) -> [LayoutGraphBuilder.Declared] {
        func isImported(_ candidate: LayoutGraphBuilder.Declared) -> Bool {
            candidate.scope.module.map { $0 != scope.module } ?? false
        }
        guard candidates.contains(where: { isImported($0) && $0.isUnavailable }),
              candidates.contains(where: { isImported($0) && !$0.isUnavailable }) else { return candidates }
        return candidates.filter { !isImported($0) || !$0.isUnavailable }
    }

    /// `candidates` without those of a module that another candidate's module re-exports: a file
    /// that sees both through that one means the re-exporter's, as Swift lets a module's own
    /// declaration shadow one it re-exports (#200). It runs only among the candidates the file
    /// already sees, so `import Alpha` alone keeps Alpha's, and an internal one of the
    /// re-exporter shadows nothing. Nor does one the file may not see: one marked `@_spi`, unless
    /// the file imports something with `@_spi` (`withoutUnopenedSPI(_:from:)` drops it before),
    /// and one under an `#if`, which a build may drop, so there the read order decides, as before.
    /// A file that imports both modules itself does not build, so each candidate's module's
    /// re-exports are enough, without the file's direct imports, except where the re-exporter's
    /// candidate is unavailable: there Swift means the re-exported one, reached another way, and
    /// a file that reaches it only through the re-exporter does not build, so an unavailable
    /// candidate shadows nothing either. It reads the writer's module and imports and each
    /// candidate's own data, so `SharedLookupKey` holds what it depends on.
    private func unshadowedByReexport(
        _ candidates: [LayoutGraphBuilder.Declared], named name: String, from scope: LayoutGraphBuilder.Scope
    ) -> [LayoutGraphBuilder.Declared] {
        guard candidates.count > 1 else { return candidates }
        let opensSPI = scope.imports?.contains(ImportExtractor.spiImport) == true
        var shadowed: Set<String> = []
        for candidate in candidates where candidate.scope.module != scope.module && !candidate.isConditional
            && !candidate.isUnavailable && (!candidate.isSPI || opensSPI) {
            shadowed.formUnion(candidate.scope.reexports ?? [])
        }
        guard !shadowed.isEmpty else { return candidates }
        return candidates.filter { candidate in
            guard let module = candidate.scope.module, module != scope.module else { return true }
            let written = modules.writtenName(of: module)
            return !shadowed.contains(module) && !shadowed.contains(written) && !shadowed.contains("\(written).\(name)")
        }
    }

    /// `members` of the type a dotted name starts at, or of the type a module-qualified name
    /// names (#245), without those an extension in a module that `scope`'s module does not load
    /// adds (`isLoaded(_:from:depth:)`). Items built without
    /// `SyntaxStructure.loadedModules` miss the imports of a file that declares nothing
    /// (`ModuleLoads.knowsEveryLoad(of:)`), so for them every member is kept when none is loaded.
    func loaded(
        _ members: [LayoutGraphBuilder.Declared], from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> [LayoutGraphBuilder.Declared] {
        let loaded = members.filter { isLoaded($0, from: scope, depth: depth) }
        guard loaded.isEmpty, let writer = scope.module, !moduleLoads.knowsEveryLoad(of: writer) else {
            return loaded
        }
        return members
    }

    /// Whether a file in `scope` sees `member`: one declared in its own module or in the module of
    /// the type it belongs to, or one an extension in a module that `scope`'s module loads adds.
    private func isLoaded(
        _ member: LayoutGraphBuilder.Declared, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> Bool {
        guard let module = member.scope.module, let writer = scope.module,
              module != owningModule(of: member, depth: depth) else { return true }
        return moduleLoads.loads(module, in: writer)
    }

    /// `name` spelled through the type its first component is another name for, as that type is
    /// recorded (`NameStart.projectType`) or spelled (`NameStart.outsideType`): `Bar.V` for
    /// `Foo.V` after `typealias Foo = ModA.Bar`, and `Array.Index` for `Arr.Index` after
    /// `typealias Arr = [Int]`, so a name the lookup finds nothing for, as a hidden nested type,
    /// comes to the name it would through a typealias of the whole. `nil` when its start is no
    /// such type, or when another type is recorded under that spelling, which an edge to the name
    /// would seem to end on, as a `Bar.V` that `Foo.V` does not mean.
    func spelledThroughStart(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> String? {
        guard let renamed = startSpelling(of: started(name, from: scope, depth: depth).start) else { return nil }
        let spelled = renamed + name.name.drop { $0 != "." }
        return typesForName[spelled] == nil ? spelled : nil
    }

    /// The name a start's type is recorded or spelled under when the first component is another
    /// name for it, `nil` otherwise.
    private func startSpelling(of start: LayoutGraphBuilder.NameStart?) -> String? {
        switch start {
        case .projectType(_, let renamed): renamed
        case .outsideType(let spelled): spelled
        case nil: nil
        }
    }

    /// The names the declarations `name` can mean are recorded under: `name` itself, and, when
    /// it starts at a type of a module (`QualifiedName.start`), `name` qualified by that module,
    /// as a type nested in `extension ModA.Foo` is recorded: `ModA.Foo.V`, which `Foo.V` means
    /// where `Foo` is ModA's. When the first component is another name for a type
    /// (`NameStart.projectType`), the rest is also looked for under the name that type is
    /// recorded under, with and without the module an extension spells it through, and
    /// qualified or not. When it is another name for a type outside the diagram
    /// (`NameStart.outsideType`), the rest is looked for under that type's name alone, since what
    /// is recorded under the name as written is another type's: after `typealias Array = Date`,
    /// `Date.V`, and not the `Array.V` that `extension [Int]` declares.
    func spellings(of name: LayoutGraphBuilder.QualifiedName) -> [String] {
        if case .outsideType(let spelled?) = name.start { return [spelled + name.name.drop { $0 != "." }] }
        guard case .projectType(let owner?, let renamed) = name.start, let module = owner.module else {
            return [name.name]
        }
        let qualifiers = Set([module, modules.writtenName(of: module)]).sorted()
        var written = [name.name]
        if let renamed {
            let rest = name.name.drop { $0 != "." }
            let unqualified = qualifiers.first { renamed.hasPrefix("\($0).") }.map { renamed.dropFirst($0.count + 1) }
            written += ([Substring(renamed)] + (unqualified.map { [$0] } ?? [])).map { "\($0)\(rest)" }
        }
        var seen: Set<String> = []
        return (written + written.flatMap { spelling in qualifiers.map { "\($0).\(spelling)" } })
            .filter { seen.insert($0).inserted }
    }
}
