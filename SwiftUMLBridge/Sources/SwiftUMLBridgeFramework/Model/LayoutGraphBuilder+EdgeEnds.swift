import Foundation

// MARK: - Edge Ends

/// What `buildClassDiagram` resolves its edges through, kept apart so the builder itself
/// stays a readable size.
extension LayoutGraphBuilder {
    /// Where a declaration lives, for picking among types that share a name.
    typealias Scope = DeclarationScope

    /// One end of a `PendingEdge`, known by node id or — until every node exists — by what owns it.
    enum EdgeEnd {
        case node(String)
        /// A type written as `name` in the inheritance clause of a declaration in `scope`, which
        /// may name a member of a type around it (`TypeLookup.qualifiedName(ofWritten:from:)`).
        case named(String, from: Scope)
        /// A particular declaration, or its name as seen from its own scope when it is not drawn.
        case declaration(ObjectIdentifier, name: String, scope: Scope)
        /// The type an extension extends, as seen from the extension's scope
        /// (`TypeLookup.extendedType(named:from:isSugared:depth:)`); the extension itself when the
        /// diagram draws no such type.
        case extended(ObjectIdentifier, name: String, scope: Scope, isSugared: Bool)
    }

    /// The type an extension extends, as the extension writes it: what
    /// `TypeLookup.extendedType(named:from:isSugared:depth:)` looks up.
    struct ExtensionTarget {
        let name: String
        let scope: Scope
        /// The extension's `SyntaxStructure.isSugared`.
        let isSugared: Bool
    }

    /// A declaration as `TypeLookup` recorded it: the name it is recorded under, and its place
    /// in recording order.
    struct RecordedDeclaration {
        let name: String
        let order: Int
        let declared: Declared
    }

    /// Which declaration a type's name means where it is written. `EdgeEndIds` resolves edge
    /// ends by it, and `mergeExtensions` picks the type an extension merges into by it, so the box
    /// that shows an extension's members is the box its nested types hang off (#107).
    struct TypeLookup {
        private var declaredForName: [String: [Declared]] = [:]
        /// `declaredForName` without its extensions, which a name never means. A name is looked
        /// up among these, so a namespace's thousand extensions do not slow a lookup of its name.
        private(set) var typesForName: [String: [Declared]] = [:]
        /// `typesForName` by the file each ranks in (`Declared.rankScope`), so a name with a
        /// candidate in the writer's own file, which `DeclarationScope.nearest` always picks, is
        /// looked up there alone.
        private(set) var typesForNameInFile: [String: [String: [Declared]]] = [:]
        /// Each declaration as recorded, by its identity.
        private(set) var recordForDeclaration: [ObjectIdentifier: RecordedDeclaration] = [:]
        /// The type each declaration's enclosing extension extends, once worked out
        /// (`enclosingExtensionType(of:depth:)`); `record` starts a new one.
        private var enclosingTypes = EnclosingTypes()
        /// The type each first component means, once worked out (`started(_:from:depth:)`);
        /// `record` and a change of `unlistedMembers` start a new one.
        private(set) var nameStarts = NameStarts()
        /// The names a type declared in an extension is recorded under, the only names a dotted
        /// name as written can be told apart by (`fitsEachAlone(_:)`).
        private var namesWithExtendedTypes: Set<String> = []
        /// Every extension recorded, with the name it was recorded under, in recording order.
        private(set) var recordedExtensions: [(name: String, declared: Declared)] = []
        /// The names a typealias is recorded under (`namesTypealias(_:)`), so asking costs no scan
        /// of a name's many same-named types.
        private(set) var aliasNames: Set<String> = []
        /// A qualifier must name one of these modules to be read as a module (#124).
        private(set) var modules = ModuleQualifiers()
        /// The nested types the items do not list, as while nested types are hidden, and their
        /// typealiases, by full name (`unlistedMembers(of:named:)`). Never what a name means:
        /// only whether an extension is of a project type goes by them.
        var unlistedMembers: [String: [Declared]] = [:] {
            didSet { nameStarts = NameStarts() }
        }
        /// Which modules each module loads, worked out once every declaration is recorded
        /// (`recordAliases(in:)`): a member that another module's extension adds is seen in the
        /// modules that load that one.
        var moduleLoads = ModuleLoads()

        /// A lookup of every type, extension and typealias in `items`, none of them drawn.
        init(of items: [SyntaxStructure] = []) {
            for item in items {
                guard let kind = item.kind, ElementKind.processable.contains(kind),
                      let name = item.fullName ?? item.name else { continue }
                record(Declared(item, kind: kind, nodeId: nil), named: name)
            }
            recordAliases(in: items)
        }

        mutating func record(_ declared: Declared, named name: String) {
            declaredForName[name, default: []].append(declared)
            if declared.isExtension {
                recordedExtensions.append((name, declared))
            } else {
                typesForName[name, default: []].append(declared)
                if let filePath = declared.rankScope.filePath {
                    typesForNameInFile[name, default: [:]][filePath, default: []].append(declared)
                }
                if declared.extended != nil { namesWithExtendedTypes.insert(name) }
            }
            if declared.aliasTarget != nil {
                aliasNames.insert(name)
            }
            recordForDeclaration[declared.declaration] = RecordedDeclaration(
                name: name, order: recordForDeclaration.count, declared: declared
            )
            if let module = declared.scope.module {
                modules.record(module)
            }
            enclosingTypes = EnclosingTypes()
            nameStarts = NameStarts()
        }

        /// The name `declaration` was recorded under.
        func recordedName(of declaration: ObjectIdentifier) -> String? {
            recordForDeclaration[declaration]?.name
        }

        /// Every declaration recorded under `name`, types, typealiases and extensions, in
        /// recording order.
        func declarations(named name: String) -> [Declared] {
            declaredForName[name] ?? []
        }

        /// The type a name means where it is written, close to how Swift looks it up: the nearest
        /// (`DeclarationScope.nearest(among:scope:)`) of the types and typealiases visible there,
        /// drawn or hidden, and for a typealias the type it aliases, as seen from the alias;
        /// `nil` when there is none, only extensions or nothing, or when the alias names a type
        /// outside the diagram, as an alias of `[Int]` always does (#126). A typealias ranks with
        /// the types, so a module's own alias shadows an imported type of its name, as in Swift
        /// (#125). A name is never matched against node ids: an undeclared `Foo_1` must not land
        /// on the node issued `Foo_1` as the second declaration of `Foo`.
        func type(named name: String, from scope: Scope, depth: Int = 0, readingModules: Bool = true) -> Declared? {
            type(QualifiedName(name: name, root: .asWritten), from: scope, depth: depth, readingModules: readingModules)
        }

        /// `type(named:from:depth:readingModules:)` for a name whose root is known
        /// (`qualifiedName(ofWritten:from:)`).
        func type(_ name: QualifiedName, from scope: Scope, depth: Int = 0, readingModules: Bool = true) -> Declared? {
            nearestMatch(name, from: scope, depth: depth, readingModules: readingModules)
                .flatMap { aliased($0.declared, depth: depth, readingModules: readingModules) }
        }

        /// Whether `name`, written in `scope`, means a type only by reading a module on the way:
        /// `ModA.Foo`, or `FA` after `typealias FA = ModA.Foo`.
        func resolvesOnlyThroughModule(_ name: String, from scope: Scope) -> Bool {
            type(named: name, from: scope, readingModules: false) == nil && type(named: name, from: scope) != nil
        }

        /// `declared` itself, or for a typealias the type it aliases, as seen from the alias. An
        /// alias of sugar means what an extension so written extends
        /// (`extendedType(named:from:isSugared:depth:)`): Swift's `Array` for `[Int]`, which is
        /// outside the diagram (#126). Each step follows one alias; Swift rejects a cycle, and the
        /// depth guard is a backstop.
        func aliased(_ declared: Declared, depth: Int, readingModules: Bool = true) -> Declared? {
            guard let target = declared.aliasTarget else { return declared }
            guard depth < 8 else { return nil }
            if declared.isSugared {
                return extendedType(named: target, from: declared.scope, isSugared: true, depth: depth + 1)
            }
            let targetName = qualifiedName(
                ofWritten: target, from: declared.scope, depth: depth + 1, readingModules: readingModules
            )
            return type(targetName, from: declared.scope, depth: depth + 1, readingModules: readingModules)
        }

        /// The name `name` comes to where it is written once every typealias it goes through is
        /// followed: `Dictionary` for `JSON` after `typealias JSON = [String: Int]`, and otherwise
        /// the name the declaration it means is recorded under — `name` itself, or `Foo` for a
        /// `ModA.Foo` read through its module, or with none, `name` through its first component's
        /// typealias (`spelledThroughStart(_:from:depth:)`). Two extensions of one type outside the diagram share
        /// this name however each spells the type. `readingModules: false` reads no module
        /// qualifier, for the text formats' supertype edges, which end on a name and so cannot
        /// tell ModA's `Foo` from another `Foo` (`TypeAliasResolver`).
        func resolvedName(of name: String, from scope: Scope, readingModules: Bool = true, depth: Int = 0) -> String {
            resolvedName(
                of: QualifiedName(name: name, root: .asWritten), from: scope, readingModules: readingModules,
                depth: depth
            )
        }

        /// `resolvedName(of:from:readingModules:depth:)` for a name whose root is known
        /// (`qualifiedName(ofWritten:from:)`).
        func resolvedName(
            of name: QualifiedName, from scope: Scope, readingModules: Bool = true, depth: Int = 0
        ) -> String {
            guard depth < 8 else { return name.name }
            guard let match = nearestMatch(name, from: scope, depth: depth, readingModules: readingModules) else {
                return spelledThroughStart(name, from: scope, depth: depth) ?? name.name
            }
            guard let target = match.declared.aliasTarget else { return match.name }
            // Sugar names the standard library's type, which no project type or alias shadows, or a
            // member path past it, kept as written (#126).
            guard !match.declared.isSugared else { return target }
            let scope = match.declared.scope
            let targetName = qualifiedName(
                ofWritten: target, from: scope, depth: depth + 1, readingModules: readingModules
            )
            return resolvedName(of: targetName, from: scope, readingModules: readingModules, depth: depth + 1)
        }

        /// The name a type written as `name` in a declaration's inheritance clause is recorded
        /// under: `<enclosing>.<name>` for the innermost type around the declaration that has
        /// such a member (`DeclarationScope.enclosingTypes`), as Swift looks a name up, and
        /// `name` itself when none does. So `class Near: Base` in `enum Outer` means
        /// `Outer.Base`, even beside a top-level `Base` (#157). An enclosing class's inherited
        /// members are not looked in. Such a member is one of the enclosing types' root
        /// (`enclosingRoot(of:depth:)`): in `extension [Int]`, `Base` is a member of Swift's
        /// `Array` or a top-level `Base`, never one nested in a project `struct Array`. A member
        /// is looked for through a module only in a type the declaration's extension names through
        /// one, as `extension ModA.Foo` does: in `extension Settings` the name `Settings` is a
        /// type, even when a target is named `Settings` too. `depth` is the lookup's own, so a
        /// cycle of aliases through an extension ends at the guards of the lookups it goes through.
        func qualifiedName(
            ofWritten name: String, from scope: Scope, depth: Int = 0, readingModules: Bool = true
        ) -> QualifiedName {
            let asWritten = QualifiedName(name: name, root: .asWritten)
            var probes = scope.enclosingTypes.map { (enclosing: $0, name: "\($0).\(name)", isRecorded: false) }
            // An extension written through a typealias, `extension Crate` after
            // `typealias Crate = Outer`, sees the members recorded under its type's own name too.
            if let typeName = extendedTypeName(around: scope, depth: depth) {
                probes.append((typeName, "\(typeName).\(name)", true))
            }
            // Most supertypes, `Encodable` say, are no enclosing type's member. Working the root
            // out takes a lookup of the enclosing extension's type, so it waits for a name a type
            // is recorded under, or one a module may be read in.
            let throughModule = { (probeName: String) in readingModules && self.mayReadModule(probeName) }
            guard probes.contains(where: { typesForName[$0.name] != nil || throughModule($0.name) }) else {
                return asWritten
            }
            let root = enclosingRoot(of: scope, depth: depth)
            return probes.lazy
                .map { probe in (probe, QualifiedName(name: probe.name, root: root, isRecorded: probe.isRecorded)) }
                .first { probe, qualified in
                    if nearestDeclaration(qualified, from: scope, depth: depth) != nil { return true }
                    // A recorded name's first component is a type, never a module qualifier.
                    guard !probe.isRecorded, throughModule(probe.name), readsModule(probe.enclosing, from: scope)
                    else { return false }
                    return moduleMatch(named: probe.name, from: scope, depth: depth) != nil
                }?.1 ?? asWritten
        }

        /// The nearest of the types and typealiases named `name` that are visible from `scope`
        /// (`nearestDeclaration(_:from:depth:)`). With none, a name whose first component names a
        /// module means the rest of the name in that module (`moduleMatch`), unless it is a member
        /// path past sugar.
        func nearestMatch(
            _ name: QualifiedName, from scope: Scope, depth: Int, readingModules: Bool = true
        ) -> Match? {
            if let nearest = nearestDeclaration(name, from: scope, depth: depth) {
                return Match(declared: nearest, name: name.name)
            }
            guard readingModules, name.root != .outsideType else { return nil }
            return moduleMatch(named: name.name, from: scope, depth: depth)
        }

        /// `nearestMatch(_:from:depth:readingModules:)` for a name as written.
        func nearestMatch(
            named name: String, from scope: Scope, depth: Int, readingModules: Bool = true
        ) -> Match? {
            let written = QualifiedName(name: name, root: .asWritten)
            return nearestMatch(written, from: scope, depth: depth, readingModules: readingModules)
        }

        /// The nearest of the types and typealiases recorded under `name` that are visible from
        /// `scope` and that it can mean there (`fitting(_:for:from:depth:)`), unless a nested type
        /// the items do not list ranks nearer (`unlistedMemberShadows(_:named:from:depth:)`).
        func nearestDeclaration(_ written: QualifiedName, from scope: Scope, depth: Int) -> Declared? {
            let name = started(written, from: scope, depth: depth)
            let nearest = localNearest(name, from: scope, depth: depth)
                ?? scope.nearest(among: candidates(name, from: scope, depth: depth), scope: \.rankScope)
            guard let nearest, !unlistedMemberShadows(nearest, named: name, from: scope, depth: depth) else {
                return nil
            }
            return nearest
        }

        /// Whether `fitting(_:for:from:depth:)` takes or drops each candidate on its own, so the
        /// candidates of one file fit as they do among the rest. A dotted name as written is fitted
        /// by what the whole set holds, but only when a type declared in an extension is among them.
        func fitsEachAlone(_ name: QualifiedName) -> Bool {
            guard name.root == .asWritten, name.name.contains(".") else { return true }
            return !spellings(of: name).contains(where: namesWithExtendedTypes.contains)
        }

        /// The nearest candidate when one ranks in `scope`'s own file, found without the rest:
        /// `DeclarationScope.nearest` picks the first visible such, under any of `name`'s spellings.
        func localNearest(_ name: QualifiedName, from scope: Scope, depth: Int) -> Declared? {
            guard let filePath = scope.filePath, fitsEachAlone(name) else { return nil }
            let local = typesFirst(spellings(of: name).flatMap { typesForNameInFile[$0]?[filePath] ?? [] })
            guard !local.isEmpty else { return nil }
            let visible = local.filter { isVisible($0, from: scope, depth: depth) }
            return fitting(visible, for: name, from: scope, depth: depth).first
        }

        /// The types and typealiases recorded under any of `name`'s spellings (`spellings(of:)`)
        /// that are visible from `scope` and that `name` can mean there.
        func candidates(_ name: QualifiedName, from scope: Scope, depth: Int) -> [Declared] {
            let visible = recorded(under: spellings(of: name)).filter { isVisible($0, from: scope, depth: depth) }
            return fitting(visible, for: name, from: scope, depth: depth)
        }

        /// The types and typealiases recorded under any of `spellings`, types first.
        private func recorded(under spellings: [String]) -> [Declared] {
            guard spellings.count > 1 else { return spellings.first.flatMap { typesForName[$0] } ?? [] }
            return typesFirst(spellings.flatMap { typesForName[$0] ?? [] })
        }

        /// `declared` with its types before its typealiases, as they are recorded under one name, so
        /// a type still comes before a typealias among equals gathered under several.
        private func typesFirst(_ declared: [Declared]) -> [Declared] {
            declared.filter { $0.aliasTarget == nil } + declared.filter { $0.aliasTarget != nil }
        }

        /// Whether a name written in `lookup` can mean `declared`, as Swift's access control
        /// allows: a `private` or `fileprivate` type only in its own file, and a type below
        /// `package` only in its own module. A file or module that is unknown on either side is
        /// taken to be the same; parsed sources always carry a file path.
        func isVisible(_ declared: Declared, from lookup: Scope, depth: Int) -> Bool {
            if lookup.filePath == nil || declared.scope.filePath == nil || lookup.filePath == declared.scope.filePath {
                return true
            }
            var required = ElementAccessibility.internal
            if let module = lookup.module, let own = declared.scope.module, module != own { required = .package }
            // `access(of:)` only lowers `ownAccess`, so a type its own access already hides needs no
            // lookup of the type its extension extends. That lookup walks every declaration of the
            // name, and doing it for each of many same-named private types was cubic in their number.
            return declared.ownAccess >= required && access(of: declared, depth: depth) >= required
        }

        /// `declared`'s access, capped by the access of the type its enclosing extension extends,
        /// as that extension's own lookup finds it. Each step resolves a shorter name, so this
        /// ends; the depth guard is a backstop.
        private func access(of declared: Declared, depth: Int) -> ElementAccessibility {
            guard depth < 8, let type = enclosingExtensionType(of: declared, depth: depth) else {
                return declared.ownAccess
            }
            return min(declared.ownAccess, access(of: type, depth: depth + 1))
        }

        /// The type `declared`'s enclosing extension extends, as that extension's own lookup finds
        /// it at `depth + 1`, or `nil` for none. It depends on the declaration alone, so it is
        /// worked out once: `access(of:depth:)` and `isInExtensionOfOutsideType(_:depth:)` ask it
        /// of every candidate of a name, and each answer is a lookup of its own.
        func enclosingExtensionType(of declared: Declared, depth: Int) -> Declared? {
            guard let extended = declared.extended else { return nil }
            return enclosingTypes.type(of: declared.declaration, depth: depth) {
                extendedType(
                    named: extended.name, from: extended.scope, isSugared: extended.isSugared, depth: depth + 1
                )
            }
        }
    }
}
