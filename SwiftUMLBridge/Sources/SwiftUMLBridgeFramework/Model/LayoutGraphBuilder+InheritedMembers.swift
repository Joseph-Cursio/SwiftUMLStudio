import Foundation

// MARK: - Inherited Members

/// The members of one name a type declares (`TypeLookup.members(named:of:from:depth:)`): those
/// recorded, and the nested types the items do not list.
private struct InheritableMembers {
    var recorded: [LayoutGraphBuilder.Declared] = []
    var hidden: [LayoutGraphBuilder.Declared] = []

    var isEmpty: Bool { recorded.isEmpty && hidden.isEmpty }
}

// How a name comes to a member a superclass declares, kept apart so the type lookup stays a
// readable size. A subclass has its superclass's nested types and typealiases as members, so
// after `class Parent { typealias P = R }` and `class Outer: Parent {}`, `Outer.P` means `R`, and
// a bare `P` written in `Outer` does too (#250). An extension of `TypeLookup` in another file does
// not see the builder's own names, so they are written out in full.
extension LayoutGraphBuilder.TypeLookup {
    /// The member a superclass declares that the dotted `name` means where `scope` writes it
    /// (`inheritedLookup(_:from:depth:readingModules:)`), or `nil` when it means none, or one the
    /// items do not list.
    func inheritedMember(
        _ name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int,
        readingModules: Bool = true
    ) -> LayoutGraphBuilder.Declared? {
        guard case .member(let member)? = inheritedLookup(
            name, from: scope, depth: depth, readingModules: readingModules
        ) else { return nil }
        return member
    }

    /// What the dotted `name` means where `scope` writes it through a member a superclass declares,
    /// or `nil` when it means none, so it is looked up as before. Swift reads the part before the
    /// last dot as a type, and when that is a class the project declares with no member of the
    /// last part, its own or one an extension the writer sees adds, looks the last part up among
    /// its superclass's, then that one's, and so on. Its own member comes first, so with one, as
    /// with no class there, the name is looked up as before; a type of another directory's, which
    /// a file read without its package may be fitted to (`fitting(_:for:from:depth:)`), is no
    /// member of it, so the inherited one comes first. When the part before the last dot is itself
    /// an inherited member, `Outer.Inner.X` with `Inner` from `Parent`, the last part is that
    /// type's own member, or one it inherits. A first component read as a module, `ModA` in
    /// `ModA.P`, is no type. The names recorded (`InheritableNames`) rule out most names before
    /// any lookup.
    func inheritedLookup(
        _ name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int,
        readingModules: Bool = true
    ) -> LayoutGraphBuilder.InheritedLookup? {
        guard depth < 8, name.root != .outsideType, mayBeInherited(name.name),
              let dot = name.name.lastIndex(of: ".") else { return nil }
        if case .outsideType = name.start { return nil }
        let container = String(name.name[..<dot])
        let isModuleFirst = name.root == .asWritten && name.start == nil && scope.module != nil
            && scope.imports != nil && !container.contains(".")
        guard !isModuleFirst else { return nil }
        let containerName = name.root == .asWritten
            ? qualifiedName(ofWritten: container, from: scope, depth: depth + 1, readingModules: readingModules)
            : LayoutGraphBuilder.QualifiedName(name: container, root: name.root, isRecorded: name.isRecorded)
        let type: LayoutGraphBuilder.Declared?
        var isInherited = false
        switch inheritedLookup(
            started(containerName, from: scope, depth: depth + 1), from: scope, depth: depth + 1,
            readingModules: readingModules
        ) {
        case .hidden:
            return .hidden

        case .member(let inherited):
            type = aliased(inherited, depth: depth + 1, readingModules: readingModules)
            isInherited = true

        case nil:
            type = self.type(containerName, from: scope, depth: depth + 1, readingModules: readingModules)
        }
        // Past a container no superclass declares, only a last part a superclass may declare counts.
        guard let type, isInherited || inheritableNames.mayBeInherited(name.name) else { return nil }
        let member = String(name.name[name.name.index(after: dot)...])
        return lookUp(member, in: type, takingOwn: isInherited, from: scope, depth: depth)
    }

    /// `member` among the members `type`'s superclasses declare, nearest first, when `type` is a
    /// class with none of its own; with `takingOwn`, as for a type itself inherited, its own first.
    private func lookUp(
        _ member: String,
        in type: LayoutGraphBuilder.Declared,
        takingOwn: Bool,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int
    ) -> LayoutGraphBuilder.InheritedLookup? {
        // A class whose members cannot be told from another's ends the walk, as before it.
        guard let own = members(named: member, of: type, from: scope, depth: depth) else { return nil }
        if takingOwn, let found = nearest(of: own, from: scope) { return found }
        guard own.isEmpty, type.superclassName != nil else { return nil }
        var seen: Set<ObjectIdentifier> = [type.declaration]
        var current = type
        while let superclass = superclass(of: current, depth: depth), seen.insert(superclass.declaration).inserted {
            guard let found = members(named: member, of: superclass, from: scope, depth: depth) else { return nil }
            if let nearest = nearest(of: found, from: scope) { return nearest }
            current = superclass
        }
        return nil
    }

    /// The nearest of `members`, types first, or `.hidden` when the items list none of them: a
    /// nested type the items do not list (`unlistedMembers`) is never what a name means, but it is
    /// what Swift finds, so neither the walk nor the lookup goes past it. `nil` when there are none.
    private func nearest(
        of members: InheritableMembers, from scope: LayoutGraphBuilder.Scope
    ) -> LayoutGraphBuilder.InheritedLookup? {
        guard !members.isEmpty else { return nil }
        let types = members.recorded.filter { $0.aliasTarget == nil }
            + members.recorded.filter { $0.aliasTarget != nil }
        return scope.nearest(among: types, scope: \.rankScope).map { .member($0) } ?? .hidden
    }

    /// Whether the dotted `name`, or the part of it before a dot, can be a member a superclass
    /// declares (`InheritableNames`), so that `Outer.Inner.X` counts when `Inner` can.
    func mayBeInherited(_ name: String) -> Bool {
        var prefix = Substring(name)
        while prefix.contains(".") {
            if inheritableNames.mayBeInherited(String(prefix)) { return true }
            prefix = prefix[..<(prefix.lastIndex(of: ".") ?? prefix.startIndex)]
        }
        return false
    }

    /// Whether `name`, written in `scope`, means a typealias a superclass declares, which a type
    /// outside the diagram's extension then stands in for as for one of the writer's own aliases
    /// (`EdgeEndIds.fallback(named:resolving:throughInheritedAlias:)`).
    func meansInheritedAlias(_ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope) -> Bool {
        inheritedMember(started(name, from: scope, depth: 0), from: scope, depth: 0)?.aliasTarget != nil
    }

    /// The superclass of the class `declared`: the type the first name of its inheritance clause
    /// means from where it is declared, when that is a class the project declares; `nil`
    /// otherwise, as for a protocol, or `NSObject`.
    func superclass(of declared: LayoutGraphBuilder.Declared, depth: Int) -> LayoutGraphBuilder.Declared? {
        guard depth < 8, let written = declared.superclassName else { return nil }
        return superclasses.type(of: declared.declaration, depth: depth) {
            let name = qualifiedName(ofWritten: written, from: declared.scope, depth: depth + 1)
            guard let type = type(name, from: declared.scope, depth: depth + 1),
                  type.kind == .class, type !== declared else { return nil }
            return type
        }
    }

    /// Whether a name written in `scope` is inside the type recorded as `recorded`, or a type nested
    /// in it, where its `private` members are seen: in its body, or in an extension of it however
    /// spelled, through a typealias or a module. Only its own file sees such a member at all
    /// (`isVisible(_:from:depth:)`).
    private func isWithin(_ recorded: String, from scope: LayoutGraphBuilder.Scope, depth: Int) -> Bool {
        let within = { (name: String) in name == recorded || name.hasPrefix("\(recorded).") }
        if scope.enclosingTypes.contains(where: within) { return true }
        guard depth < 8, let enclosing = scope.enclosingExtension,
              let type = extendedType(
                  named: enclosing.name, from: scope.fileScope, isSugared: enclosing.isSugared, depth: depth + 1
              ),
              let name = recordedName(of: type.declaration) else { return false }
        return within(name)
    }

    /// The types and typealiases named `member` that `type` itself declares, in its body or in an
    /// extension, that `scope` sees, and those nested types the items do not list
    /// (`unlistedMembers`). They are recorded under the name `type` is recorded under, or that
    /// name qualified by its module, as `extension ModA.Foo` records them (`spellings(of:)`), and
    /// belong to `type`'s own outermost declaration (`owningDeclaration(of:depth:)`), so a
    /// same-named type's of another file is none of them; or under the name an extension of it
    /// writes, through a typealias or a module, as `extension Crate` and `extension Main.Outer`
    /// record theirs. A `private` one is seen only inside `type` (`isWithin(_:from:depth:)`).
    /// `nil` for a type with no outermost declaration of its own to tell its members by, as one
    /// declared in an extension of a type outside the diagram.
    private func members(
        named member: String, of type: LayoutGraphBuilder.Declared, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> InheritableMembers? {
        guard let recorded = recordedName(of: type.declaration),
              let owner = owningDeclaration(of: type, depth: depth) else { return nil }
        let start = LayoutGraphBuilder.NameStart.projectType(owningType(of: type, depth: depth), renamedTo: nil)
        let name = LayoutGraphBuilder.QualifiedName(name: "\(recorded).\(member)", root: .asWritten, start: start)
        // Worked out once, for the first private candidate.
        lazy var isInside = isWithin(recorded, from: scope, depth: depth)
        let sees = { (candidate: LayoutGraphBuilder.Declared) -> Bool in
            guard self.isVisible(candidate, from: scope, depth: depth) else { return false }
            guard candidate.isPrivate else { return true }
            return isInside
        }
        let isOwn = { (candidate: LayoutGraphBuilder.Declared) in
            self.owningDeclaration(of: candidate, depth: depth).map { $0 == owner } == true && sees(candidate)
        }
        let spelled = spellings(of: name)
        // One its body declares ranks in its own file, found without the many same-named members
        // of other files; Swift rejects a second one an extension would add.
        if let file = owner.filePath {
            let body = spelled.flatMap { typesForNameInFile[$0]?[file] ?? [] }.filter(isOwn)
            if !body.isEmpty { return InheritableMembers(recorded: body) }
        }
        let recordedMembers = spelled.flatMap { typesForName[$0] ?? [] }.filter(isOwn)
        let respelled = membersRespelled(
            named: member, of: type, besides: Set(recordedMembers.map(\.declaration)), depth: depth, sees: sees
        )
        return InheritableMembers(
            recorded: loaded(recordedMembers + respelled.own, from: scope, depth: depth),
            hidden: loaded(spelled.flatMap { unlistedMembers[$0] ?? [] }.filter(isOwn), from: scope, depth: depth)
                + respelled.unsure
        )
    }

    /// The types and typealiases named `member` that an extension of `type` declares, other than
    /// those `besides`, when it spells `type` another way than it is recorded, through a typealias or a
    /// module, and so records them under that name. `unsure` holds those of an extension whose
    /// type the lookup cannot find, but which may be `type`: `extension Main.Outer`, read with no
    /// module known. Its member may be the one Swift means, so the walk goes no further, and the
    /// name is looked up as before. With modules known, such an extension's type is found, or is
    /// outside the diagram, as `String.Index` is.
    private func membersRespelled(
        named member: String,
        of type: LayoutGraphBuilder.Declared,
        besides found: Set<ObjectIdentifier>,
        depth: Int,
        sees: (LayoutGraphBuilder.Declared) -> Bool
    ) -> (own: [LayoutGraphBuilder.Declared], unsure: [LayoutGraphBuilder.Declared]) {
        let recorded = recordedName(of: type.declaration) ?? ""
        var own: [LayoutGraphBuilder.Declared] = []
        var unsure: [LayoutGraphBuilder.Declared] = []
        for candidate in inheritableNames.extensionMembers(named: member) {
            guard !found.contains(candidate.declaration), let extended = candidate.extended,
                  recordedName(of: candidate.declaration) == "\(extended.name).\(member)", sees(candidate) else {
                continue
            }
            if let extendedType = enclosingExtensionType(of: candidate, depth: depth) {
                if extendedType === type { own.append(candidate) }
            } else if candidate.scope.module == nil, extended.name.hasSuffix(".\(recorded)") {
                unsure.append(candidate)
            }
        }
        return (own, unsure)
    }
}

extension LayoutGraphBuilder {
    /// What a name means through a member a superclass declares (`TypeLookup.inheritedLookup`).
    enum InheritedLookup {
        /// The member, a type or typealias the items list.
        case member(Declared)
        /// A nested type the items do not list, which the name means and no lookup goes past.
        case hidden
    }
}

extension LayoutGraphBuilder {
    /// What `TypeLookup` records of each name to rule out, before any lookup, a dotted name that
    /// cannot be a member a superclass declares (`TypeLookup.inheritedMember`): its last part must
    /// be a member of a type named like one a class names as its superclass, or like a typealias's
    /// target that is, and the part before that named like a class with a supertype, or a
    /// typealias, which may be another name for one. Names are compared by their last part alone,
    /// so this rules out without ruling in.
    struct InheritableNames {
        /// The last part of each class with a supertype and of each typealias.
        private var containers: Set<String> = []
        /// The members of a type named like a superclass.
        private var members: Set<String> = []
        /// The members recorded under each type's last part.
        private var membersOf: [String: Set<String>] = [:]
        /// The last part of each superclass as written, and of what a typealias of one aliases.
        private var superclasses: Set<String> = []
        /// The last part of each typealias's target, by the alias's last part.
        private var aliasTargets: [String: Set<String>] = [:]
        /// The types and typealiases declared in an extension, by their last part, as an extension
        /// spelled through a typealias or a module records them under a name its type has not.
        private var membersInExtensions: [String: [Declared]] = [:]

        /// Records `declared`, a type or typealias recorded under `name`, with the superclass a
        /// class names, and the target a typealias names. One the items do not list
        /// (`TypeLookup.unlistedMembers`, `isListed`) counts for the names alone, as recording
        /// those again, as each change of them does, changes nothing.
        mutating func record(_ declared: Declared, named name: String, isListed: Bool = true) {
            let (superclass, aliasTarget) = (declared.superclassName, declared.aliasTarget)
            let parts = name.split(separator: ".").map(String.init)
            guard let last = parts.last else { return }
            if isListed, declared.extended != nil { membersInExtensions[last, default: []].append(declared) }
            if parts.count > 1 {
                let container = parts[parts.count - 2]
                membersOf[container, default: []].insert(last)
                if superclasses.contains(container) { members.insert(last) }
            }
            if superclass != nil || aliasTarget != nil { containers.insert(last) }
            if let aliasTarget {
                let target = Self.lastPart(of: aliasTarget)
                aliasTargets[last, default: []].insert(target)
                if superclasses.contains(last) { addSuperclass(target) }
            }
            if let superclass { addSuperclass(Self.lastPart(of: superclass)) }
        }

        /// The types and typealiases named `member` declared in an extension.
        func extensionMembers(named member: String) -> [Declared] {
            membersInExtensions[member] ?? []
        }

        /// Whether the dotted `name` can be a member a superclass declares.
        func mayBeInherited(_ name: String) -> Bool {
            guard let dot = name.lastIndex(of: "."), members.contains(String(name[name.index(after: dot)...])) else {
                return false
            }
            return containers.contains(Self.lastPart(of: String(name[..<dot])))
        }

        /// Adds `name` to the superclasses, and what each typealias of that name aliases, however
        /// long the chain.
        private mutating func addSuperclass(_ name: String) {
            var pending = [name]
            while let next = pending.popLast() {
                guard superclasses.insert(next).inserted else { continue }
                members.formUnion(membersOf[next] ?? [])
                pending += aliasTargets[next] ?? []
            }
        }

        private static func lastPart(of name: String) -> String {
            String(name.removeAngleBracketsWithContent().split(separator: ".").last ?? "")
        }
    }
}
