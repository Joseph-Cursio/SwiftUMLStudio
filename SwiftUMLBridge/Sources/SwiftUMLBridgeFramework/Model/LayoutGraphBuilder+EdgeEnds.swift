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

    /// A declaration, as `TypeLookup` needs it to choose among same-named types.
    struct Declared {
        /// `nil` for a type the diagram hides: it has no node, but still takes its name's lookup.
        let nodeId: String?
        let declaration: ObjectIdentifier
        let kind: ElementKind
        let isExtension: Bool
        let scope: Scope
        /// The most restrictive access level of the declaration and the declarations enclosing
        /// it, with an enclosing extension's modifier applied. `TypeLookup.access(of:)` also caps
        /// it by the type that extension extends.
        let ownAccess: ElementAccessibility
        /// The type the enclosing extension extends, as written there, when there is one.
        let extended: ExtensionTarget?
        /// For a typealias, the name of the type it aliases, looked up from its own scope (#125).
        let aliasTarget: String?
        /// For an extension or a typealias, `SyntaxStructure.isSugared`: its name, or its
        /// `aliasTarget`, is a standard-library type's, whatever the project declares (#126).
        let isSugared: Bool

        /// `container` is the declaration `item` is a member of, when `item.parent` is not set:
        /// a typealias is never flattened out of its type's members.
        init(_ item: SyntaxStructure, kind: ElementKind, nodeId: String?, in container: SyntaxStructure? = nil) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(item)
            self.kind = kind
            isExtension = kind == .extension
            aliasTarget = kind == .typealias ? item.typename : nil
            isSugared = item.isSugared
            scope = Scope(of: item, in: container)
            // Extensions are top level, so a chain holds at most one, last.
            let chain = Array(sequence(first: item) { $0 === item ? container ?? $0.parent : $0.parent })
            let declared = chain.prefix { $0.kind != .extension }
            var levels = declared.map { $0.accessibility.flatMap { $0 == .other ? nil : $0 } ?? .internal }
            if let enclosing = chain.first(where: { $0.kind == .extension }), !levels.isEmpty,
               let modifier = enclosing.accessibility {
                // `private extension` and `fileprivate extension` cap what they hold; `public` and
                // `package` ones set their members' default, which the parser reports as internal.
                if modifier == .private || modifier == .fileprivate {
                    levels.append(modifier)
                } else if modifier >= .package, levels[levels.count - 1] == .internal {
                    levels[levels.count - 1] = min(modifier, .public)
                }
            }
            ownAccess = levels.min() ?? .internal
            extended = chain.first { $0.kind == .extension && $0 !== item }.flatMap { enclosing in
                enclosing.name.map {
                    ExtensionTarget(name: $0, scope: Scope(of: enclosing), isSugared: enclosing.isSugared)
                }
            }
        }
    }

    /// Which declaration a type's name means where it is written. `EdgeEndIds` resolves edge
    /// ends by it, and `mergeExtensions` picks the type an extension merges into by it, so the box
    /// that shows an extension's members is the box its nested types hang off (#107).
    struct TypeLookup {
        private var declaredForName: [String: [Declared]] = [:]
        /// `declaredForName` without its extensions, which a name never means. A name is looked
        /// up among these, so a namespace's thousand extensions do not slow a lookup of its name.
        private(set) var typesForName: [String: [Declared]] = [:]
        /// `typesForName` by the file each was declared in, so a name with a candidate in the
        /// writer's own file, which `DeclarationScope.nearest` always picks, is looked up there alone.
        private(set) var typesForNameInFile: [String: [String: [Declared]]] = [:]
        /// The type each declaration's enclosing extension extends, once worked out
        /// (`enclosingExtensionType(of:depth:)`); `record` starts a new one.
        private var enclosingTypes = EnclosingTypes()
        /// The names a type declared in an extension is recorded under, the only names a dotted
        /// name as written can be told apart by (`fitsEachAlone(_:)`).
        private var namesWithExtendedTypes: Set<String> = []
        /// Every extension recorded, with the name it was recorded under, in recording order.
        private(set) var recordedExtensions: [(name: String, declared: Declared)] = []
        /// The name each declaration was first recorded under.
        private var nameForDeclaration: [ObjectIdentifier: String] = [:]
        /// The names a typealias is recorded under (`namesTypealias(_:)`), so asking costs no scan
        /// of a name's many same-named types.
        private(set) var aliasNames: Set<String> = []
        /// The nested types the items do not list, as while nested types are hidden, and their
        /// typealiases, by full name (`unlistedMembers(of:named:)`). Never what a name means:
        /// only whether an extension is of a project type goes by them.
        var unlistedMembers: [String: [Declared]] = [:]

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
                if let filePath = declared.scope.filePath {
                    typesForNameInFile[name, default: [:]][filePath, default: []].append(declared)
                }
                if declared.extended != nil { namesWithExtendedTypes.insert(name) }
                if declared.kind == .typealias { aliasNames.insert(name) }
            }
            if nameForDeclaration[declared.declaration] == nil {
                nameForDeclaration[declared.declaration] = name
            }
            enclosingTypes = EnclosingTypes()
        }

        /// The name `declaration` was recorded under.
        func recordedName(of declaration: ObjectIdentifier) -> String? {
            nameForDeclaration[declaration]
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
        func type(named name: String, from scope: Scope, depth: Int = 0) -> Declared? {
            type(QualifiedName(name: name, root: .asWritten), from: scope, depth: depth)
        }

        /// `type(named:from:depth:)` for a name whose root is known
        /// (`qualifiedName(ofWritten:from:)`).
        func type(_ name: QualifiedName, from scope: Scope, depth: Int = 0) -> Declared? {
            nearestDeclaration(name, from: scope, depth: depth).flatMap { aliased($0, depth: depth) }
        }

        /// `declared` itself, or for a typealias the type it aliases, as seen from the alias. An
        /// alias of sugar means what an extension so written extends
        /// (`extendedType(named:from:isSugared:depth:)`): Swift's `Array` for `[Int]`, which is
        /// outside the diagram (#126). Each step follows one alias; Swift rejects a cycle, and the
        /// depth guard is a backstop.
        private func aliased(_ declared: Declared, depth: Int) -> Declared? {
            guard let target = declared.aliasTarget else { return declared }
            guard depth < 8 else { return nil }
            if declared.isSugared {
                return extendedType(named: target, from: declared.scope, isSugared: true, depth: depth + 1)
            }
            let targetName = qualifiedName(ofWritten: target, from: declared.scope, depth: depth + 1)
            return type(targetName, from: declared.scope, depth: depth + 1)
        }

        /// The name `name` comes to where it is written once every typealias it goes through is
        /// followed: `Dictionary` for `JSON` after `typealias JSON = [String: Int]`, and `name`
        /// itself when the declaration it means is no typealias. Two extensions of one type
        /// outside the diagram share this name however each spells the type.
        func resolvedName(of name: String, from scope: Scope, depth: Int = 0) -> String {
            resolvedName(of: QualifiedName(name: name, root: .asWritten), from: scope, depth: depth)
        }

        /// `resolvedName(of:from:depth:)` for a name whose root is known
        /// (`qualifiedName(ofWritten:from:)`).
        func resolvedName(of name: QualifiedName, from scope: Scope, depth: Int = 0) -> String {
            guard depth < 8, let nearest = nearestDeclaration(name, from: scope, depth: depth),
                  let target = nearest.aliasTarget else { return name.name }
            // Sugar names the standard library's type, which no project type or alias shadows, or a
            // member path past it, kept as written (#126).
            guard !nearest.isSugared else { return target }
            let targetName = qualifiedName(ofWritten: target, from: nearest.scope, depth: depth + 1)
            return resolvedName(of: targetName, from: nearest.scope, depth: depth + 1)
        }

        /// The name a type written as `name` in a declaration's inheritance clause is recorded
        /// under: `<enclosing>.<name>` for the innermost type around the declaration that has
        /// such a member (`DeclarationScope.enclosingTypes`), as Swift looks a name up, and
        /// `name` itself when none does. So `class Near: Base` in `enum Outer` means
        /// `Outer.Base`, even beside a top-level `Base` (#157). An enclosing class's inherited
        /// members are not looked in. Such a member is one of the enclosing types' root
        /// (`enclosingRoot(of:depth:)`): in `extension [Int]`, `Base` is a member of Swift's
        /// `Array` or a top-level `Base`, never one nested in a project `struct Array`. `depth`
        /// is the lookup's own, so a cycle of aliases through an extension ends at the guards of
        /// the lookups it goes through.
        func qualifiedName(ofWritten name: String, from scope: Scope, depth: Int = 0) -> QualifiedName {
            let asWritten = QualifiedName(name: name, root: .asWritten)
            var names = scope.enclosingTypes.map { "\($0).\(name)" }
            // An extension written through a typealias, `extension Crate` after
            // `typealias Crate = Outer`, sees the members recorded under its type's own name too.
            if let typeName = extendedTypeName(around: scope, depth: depth) { names.append("\(typeName).\(name)") }
            // Most supertypes, `Encodable` say, are no enclosing type's member. Working the root
            // out takes a lookup of the enclosing extension's type, so it waits for a name a type
            // is recorded under.
            guard names.contains(where: { typesForName[$0] != nil }) else { return asWritten }
            let root = enclosingRoot(of: scope, depth: depth)
            return names.lazy.map { QualifiedName(name: $0, root: root) }
                .first { nearestDeclaration($0, from: scope, depth: depth) != nil } ?? asWritten
        }

        /// The nearest of the types and typealiases recorded under `name` that are visible from
        /// `scope` and that it can mean there (`fitting(_:for:from:depth:)`).
        func nearestDeclaration(_ name: QualifiedName, from scope: Scope, depth: Int) -> Declared? {
            if let local = localNearest(name, from: scope, depth: depth) { return local }
            return scope.nearest(among: candidates(name, from: scope, depth: depth), scope: \.scope)
        }

        /// Whether `fitting(_:for:from:depth:)` takes or drops each candidate on its own, so the
        /// candidates of one file fit as they do among the rest. A dotted name as written is fitted
        /// by what the whole set holds, but only when a type declared in an extension is among them.
        private func fitsEachAlone(_ name: QualifiedName) -> Bool {
            !(name.root == .asWritten && name.name.contains(".")) || !namesWithExtendedTypes.contains(name.name)
        }

        /// The nearest candidate when one is in `scope`'s own file, found without the rest: one in
        /// the same file is always visible, and `DeclarationScope.nearest` picks the first such.
        private func localNearest(_ name: QualifiedName, from scope: Scope, depth: Int) -> Declared? {
            guard let filePath = scope.filePath, fitsEachAlone(name),
                  let local = typesForNameInFile[name.name]?[filePath] else { return nil }
            return fitting(local, for: name, from: scope, depth: depth).first
        }

        private func candidates(_ name: QualifiedName, from scope: Scope, depth: Int) -> [Declared] {
            let visible = (typesForName[name.name] ?? []).filter { isVisible($0, from: scope, depth: depth) }
            return fitting(visible, for: name, from: scope, depth: depth)
        }

        /// `type(_:from:depth:)`, and, when that is a protocol, whether it surely is: the nearest
        /// candidate is one in the writer's own file or module, or the only one, or every
        /// candidate comes to a protocol, and a typealias on the way was as sure. Imports are not
        /// tracked, so among same-named types of other modules the nearest is a guess, which may
        /// be one the writer does not import. Only a protocol names an edge apart, so no other
        /// kind costs a check. `kinds` keeps each typealias's kind once worked out, and the answer
        /// for a writer with no candidate in its own file, which depends on its module alone:
        /// without them, a name many same-named aliases share looked each alias's target up for
        /// every edge, and every alias of a chain the next one's.
        func typeWithSureKind(
            _ name: QualifiedName, from scope: Scope, depth: Int = 0, kinds: AliasKinds
        ) -> (type: Declared?, kindIsSure: Bool) {
            // The writer's own candidate is the nearest, and surely the one it means.
            if let local = localNearest(name, from: scope, depth: depth) {
                let resolved = resolvedType(of: local, depth: depth, kinds: kinds)
                guard resolved.type?.kind == .protocol else { return (resolved.type, true) }
                return (resolved.type, resolved.isSure)
            }
            guard scope.filePath != nil, fitsEachAlone(name) else {
                return uncachedTypeWithSureKind(name, from: scope, depth: depth, kinds: kinds)
            }
            let key = SharedLookupKey(name: name.name, root: name.root, module: scope.module, depth: depth)
            if let known = kinds.shared[key] { return known }
            let result = uncachedTypeWithSureKind(name, from: scope, depth: depth, kinds: kinds)
            kinds.shared[key] = result
            return result
        }

        private func uncachedTypeWithSureKind(
            _ name: QualifiedName, from scope: Scope, depth: Int, kinds: AliasKinds
        ) -> (type: Declared?, kindIsSure: Bool) {
            let found = candidates(name, from: scope, depth: depth)
            guard let nearest = scope.nearest(among: found, scope: \.scope) else { return (nil, true) }
            let resolved = resolvedType(of: nearest, depth: depth, kinds: kinds)
            let type = resolved.type
            guard type?.kind == .protocol else { return (type, true) }
            guard resolved.isSure else { return (type, false) }
            let isOwn = scope.filePath.map { $0 == nearest.scope.filePath } == true
                || scope.module.map { $0 == nearest.scope.module } == true
            guard found.count > 1, !isOwn else { return (type, true) }
            return (type, found.allSatisfy { resolvedKind(of: $0, depth: depth, kinds: kinds) == (.protocol, true) })
        }

        /// The kind `declared` comes to, through a typealias the kind of the type it aliases, or
        /// `nil` for one outside the diagram, and whether that is sure (`typeWithSureKind`). Each
        /// step follows one alias, as `aliased(_:depth:)` does, so a cycle of them ends at the
        /// same depth guard, unsure.
        private func resolvedKind(
            of declared: Declared, depth: Int, kinds: AliasKinds
        ) -> (kind: ElementKind?, isSure: Bool) {
            if declared.aliasTarget != nil, declared.isSugared { return (nil, true) }
            let resolved = resolvedType(of: declared, depth: depth, kinds: kinds)
            return (resolved.type?.kind, resolved.isSure)
        }

        /// `aliased(_:depth:)`, and whether the kind of what it comes to is sure, kept in `kinds`
        /// for each typealias: the type is the one `typeWithSureKind` finds for the alias's
        /// target, so a chain's last link, in another file, is looked up once for the writer's
        /// module, not once per alias.
        private func resolvedType(
            of declared: Declared, depth: Int, kinds: AliasKinds
        ) -> (type: Declared?, isSure: Bool) {
            guard let target = declared.aliasTarget else { return (declared, true) }
            if declared.isSugared { return (aliased(declared, depth: depth), true) }
            guard depth < 8 else { return (nil, false) }
            if let known = kinds[declared.declaration, depth] { return known }
            let targetName = qualifiedName(ofWritten: target, from: declared.scope, depth: depth + 1)
            let (type, isSure) = typeWithSureKind(targetName, from: declared.scope, depth: depth + 1, kinds: kinds)
            kinds[declared.declaration, depth] = (type, isSure)
            return (type, isSure)
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
