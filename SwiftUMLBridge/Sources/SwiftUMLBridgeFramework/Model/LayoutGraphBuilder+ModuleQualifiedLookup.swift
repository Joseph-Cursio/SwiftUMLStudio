import Foundation

// MARK: - Module Qualifiers

/// How `TypeLookup` reads a name's first component as a module (#124), kept apart so the lookup
/// itself stays a readable size.
extension LayoutGraphBuilder.TypeLookup {
    typealias Declared = LayoutGraphBuilder.Declared
    typealias Scope = LayoutGraphBuilder.Scope

    /// The declaration a name means, and the name it is recorded under.
    struct Match {
        let declared: Declared
        let name: String
    }

    /// `ModA.Foo.Inner` read as ModA's `Foo.Inner` (#124): the rest of the name, among the
    /// declarations whose outermost type is in a module the first component names
    /// (`ModuleQualifiers`), so a `Foo.Inner` another module adds to ModA's `Foo` counts.
    /// Swift reads a type before a module of its name, so this runs only when the full name
    /// means nothing — `Networking.Request` stays the type nested in an `enum Networking` — and
    /// not when a visible type named like the qualifier is declared in the writer's own module
    /// or the module named. Imports are not tracked, so a type of that name in any other
    /// module is taken to be one the file does not import.
    func moduleMatch(named name: String, from scope: Scope, depth: Int) -> Match? {
        guard let dot = name.firstIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
        let qualifier = String(name[..<dot])
        let named = modules.modules(namedBy: qualifier)
        guard !named.isEmpty else { return nil }
        let shadowing = declarations(named: qualifier).contains { declared in
            guard !declared.isExtension else { return false }
            let module = declared.scope.module
            return (module == nil || module == scope.module || named.contains(module ?? ""))
                && isVisible(declared, from: scope, depth: depth)
        }
        guard !shadowing else { return nil }
        let rest = String(name[name.index(after: dot)...])
        let candidates = declarations(named: rest).filter {
            !$0.isExtension && isVisible($0, from: scope, depth: depth)
                && owningModule(of: $0, depth: depth).map(named.contains) == true
        }
        return scope.nearest(among: candidates, scope: \.scope).map { Match(declared: $0, name: rest) }
    }

    /// The module of the outermost type `declared` belongs to: its own, or for a declaration
    /// in an extension, that of the type the extension extends, as the extension finds it.
    func owningModule(of declared: Declared, depth: Int) -> String? {
        guard let extended = declared.extended else { return declared.scope.module }
        guard depth < 8, let type = type(named: extended.name, from: extended.scope, depth: depth + 1) else {
            return nil
        }
        return owningModule(of: type, depth: depth + 1)
    }

    /// The names an extension can spell the type `declaration` with and still stand in for it
    /// when it is hidden: its own name, and that name qualified by its module (`ModA.Foo.Inner`).
    /// A spelling through a typealias is not read, as the text formats' supertype edges, which
    /// end on a name, do not read it either.
    func spellings(of declaration: ObjectIdentifier) -> [String] {
        guard let recorded = recordForDeclaration[declaration] else { return [] }
        let module = owningModule(of: recorded.declared, depth: 0)
        return [recorded.name] + (module.map(ModuleQualifiers.spellings(of:)) ?? []).sorted()
            .map { "\($0).\(recorded.name)" }
    }

    /// The extensions recorded under any of `names`, each with its name, in recording order.
    func extensions(named names: [String]) -> [(name: String, declared: Declared)] {
        let order = { (declared: Declared) in self.recordForDeclaration[declared.declaration]?.order ?? 0 }
        return names.flatMap { name in declarations(named: name).filter(\.isExtension).map { (name, $0) } }
            .sorted { order($0.declared) < order($1.declared) }
    }
}
