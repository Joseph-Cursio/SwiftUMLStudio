// MARK: - Name Starts Without a Module

// What a dotted name as written starts at in a file of no known module, as sources read without
// their package are, kept apart from `NameStart` so each file stays a readable size. With no
// module and imports to share a start by, only a first component that is another name for a type
// gets one, or is spelled through the alias.
extension LayoutGraphBuilder.TypeLookup {
    /// `started(_:from:depth:)` for a file of no known module or imports, as sources read
    /// without their package are (#283): the name gets a start only when its first component
    /// `first` is another name for a project type (`NameStart.projectType`'s `renamedTo`), as
    /// `typealias Q = Other` makes `Q` of `Other`, in the writer's file or a type around it, so
    /// `Q.Foo` is also looked for under `Other.Foo` (`spellings(of:)`). Any other first component
    /// gets none. Writers at file scope whose own file declares no `first` share the answer by
    /// their imports and directory (`NameStarts`), all a directory's ranking goes by there; any
    /// other writer keeps it by its whole scope, as each step of one lookup asks for it again.
    func startedWithoutModule(
        _ name: LayoutGraphBuilder.QualifiedName, first: String, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.QualifiedName {
        guard depth < 8 else { return name }
        func lookUp() -> LayoutGraphBuilder.NameStart? {
            guard let type = firstComponentType(of: name.name, from: scope, depth: depth),
                  let recorded = recordedName(of: type.declaration), recorded != first,
                  let owner = owningType(of: type, depth: depth + 1) else { return nil }
            return .projectType(owner, renamedTo: recorded)
        }
        var started = name
        if scope.enclosingTypes.isEmpty, scope.enclosingExtension == nil, let filePath = scope.filePath,
           typesForNameInFile[first]?[filePath] == nil {
            let key = LayoutGraphBuilder.NameStartKey(
                first: first, module: nil, imports: scope.imports, directory: scope.rankingDirectory, depth: depth
            )
            started.start = nameStarts.startWithoutModule(for: key, lookUp: lookUp)
        } else {
            let key = LayoutGraphBuilder.ScopedNameStartKey(
                first: first, filePath: scope.filePath, imports: scope.imports, reexports: scope.reexports,
                enclosingTypes: scope.enclosingTypes, enclosingExtension: scope.enclosingExtension?.name,
                isSugared: scope.enclosingExtension?.isSugared ?? false, depth: depth
            )
            started.start = nameStarts.startWithoutModule(for: key, lookUp: lookUp)
        }
        return started
    }

    /// In a file of no known module, the `candidates` of a dotted name started at another name for
    /// a project type (`startedWithoutModule`) that belong to a type of that type's name, outermost
    /// past any extension (`owningType(of:depth:)`): after `typealias Q = Other`, the `Foo`s of
    /// each `Other`, and not those of another directory's `enum Q`. With none, as with a module,
    /// those `fallbackCandidates(_:for:from:depth:)` keeps: the type a member belongs to can be
    /// misread, as for one in an extension spelled through a chain of aliases that leads back
    /// through the first (`AliasChainWalkTests`). `amongSameNamedTypes` is whether the project
    /// declares more than one type of that name. Then `fitting(_:for:from:depth:)` keeps those
    /// of the very `Other` the alias names, by its name and file (`membersOfWrittenStart`), every
    /// time, as same-named types may each declare the member in their body: so neither the
    /// writer's own `Other` nor one in a directory that sorts first is taken. A `public` member of
    /// that type's body comes before an extension's in another directory there (#253), and when
    /// the declaration the alias names has none, as for two declarations of one type, each under
    /// its own `#if`, every one of the type's name still counts. `nil` for any other start or
    /// scope, whose members `members(of:among:from:depth:)` picks.
    func membersOfRenamedStart(
        _ candidates: [LayoutGraphBuilder.Declared],
        for name: LayoutGraphBuilder.QualifiedName,
        from scope: LayoutGraphBuilder.Scope,
        depth: Int
    ) -> (members: [LayoutGraphBuilder.Declared], amongSameNamedTypes: Bool)? {
        guard startsAtAliasWithoutModule(name, from: scope), case .projectType(let owner?, _) = name.start,
              let typeName = owner.name else { return nil }
        // A member of an extension of a type outside the diagram has no owning type, so never counts.
        let members = candidates.filter { owningType(of: $0, depth: depth)?.name == typeName }
        let kept = members.isEmpty ? fallbackCandidates(candidates, for: name, from: scope, depth: depth) : members
        return (kept, declarations(named: typeName).count { !$0.isExtension } > 1)
    }

    /// Whether `name`, written in a file of no known module, starts at another name for a project
    /// type (`startedWithoutModule`). Its candidates are then fitted only together
    /// (`fitsEachAlone(_:from:)`): which of the same-named types the alias names is told from the
    /// whole set (`membersOfRenamedStart`), so the writer's own file, which may declare another of
    /// them, cannot answer alone, nor can writers share what the set comes to.
    func startsAtAliasWithoutModule(
        _ name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope
    ) -> Bool {
        guard scope.module == nil, case .projectType(_, _?) = name.start else { return false }
        return true
    }

    /// The start of the dotted name `name` written in a file of no known module, as sources read
    /// without their package are, where `started(_:from:depth:)` works out none, when its first
    /// component, read as a bare name (`firstComponentType(of:from:depth:)`), is a type outside
    /// the diagram: spelled through the typealias that component is (`outsideSpelling`). So
    /// `Base.Inner` after `typealias Base = Second` is `Second.Inner`, and two directories' own
    /// `typealias Base` and `extension Base.Inner` stay apart, as two targets' do. With no
    /// modules, a leading component of what the alias comes to may be one, so a spelling that
    /// ends in a name the project records, as `Main.Real` after `typealias O = Main.Real` in the
    /// module `Main`, may be the project's own `Real` and is no sure outside type. `nil` for any
    /// other name; only the spelling reads it, never the lookup's candidates.
    func outsideStartWithoutModule(
        of name: LayoutGraphBuilder.QualifiedName, from scope: LayoutGraphBuilder.Scope, depth: Int
    ) -> LayoutGraphBuilder.NameStart? {
        guard scope.module == nil, name.root == .asWritten, name.start == nil,
              let dot = name.name.firstIndex(of: "."),
              firstComponentType(of: name.name, from: scope, depth: depth) == nil,
              let spelled = outsideSpelling(of: String(name.name[..<dot]), from: scope, depth: depth)
        else { return nil }
        let parts = spelled.split(separator: ".")
        guard !parts.indices.contains(where: { typesForName[parts[$0...].joined(separator: ".")] != nil }) else {
            return nil
        }
        return .outsideType(spelledAs: spelled)
    }
}
