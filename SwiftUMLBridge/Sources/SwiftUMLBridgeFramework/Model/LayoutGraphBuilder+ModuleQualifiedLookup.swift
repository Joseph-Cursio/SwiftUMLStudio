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
    /// not when a type named like the qualifier is in the way (`shadows`).
    func moduleMatch(named name: String, from scope: Scope, depth: Int) -> Match? {
        guard let dot = name.firstIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
        let qualifier = String(name[..<dot])
        let named = modules.modules(namedBy: qualifier)
        let rest = String(name[name.index(after: dot)...])
        guard !named.isEmpty, !shadows(qualifier, modules: named, rest: rest, from: scope, depth: depth) else {
            return nil
        }
        let candidates = declarations(named: rest).filter {
            !$0.isExtension && isVisible($0, from: scope, depth: depth)
                && owningModule(of: $0, depth: depth).map(named.contains) == true
        }
        return scope.nearest(among: candidates, scope: \.scope).map { Match(declared: $0, name: rest) }
    }

    /// Whether a visible type named `qualifier` keeps it from naming `modules` where `scope`
    /// writes `<qualifier>.<rest>`. One in the writer's own module, or in a module the qualifier
    /// names, always does: Swift sees it. Imports are not tracked, so one in another module counts
    /// only when it declares a member named like the next component, as it must when the code
    /// means it; a namespace `enum Analytics` in a module the file does not import, with no
    /// `Event` in it, leaves `Analytics.Event` to the module Analytics.
    private func shadows(
        _ qualifier: String, modules named: Set<String>, rest: String, from scope: Scope, depth: Int
    ) -> Bool {
        let next = String(rest.prefix { $0 != "." })
        return declarations(named: qualifier).contains { declared in
            guard !declared.isExtension, isVisible(declared, from: scope, depth: depth) else { return false }
            guard let module = declared.scope.module, module != scope.module, !named.contains(module) else {
                return true
            }
            return declared.memberTypeNames.contains(next)
        }
    }

    /// Whether `name`, written in `scope`, means a type only once its first component is read as
    /// a module: `ModA.Foo`, but not `Foo`, nor `Outer.Inner` for a nested type.
    func readsModule(_ name: String, from scope: Scope) -> Bool {
        nearestMatch(named: name, from: scope, depth: 0, readingModules: false) == nil
            && moduleMatch(named: name, from: scope, depth: 0) != nil
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

    /// The name the declaration `name` means is recorded under, before any typealias is
    /// followed: `StoreType` for `Lib.StoreType`; `nil` when it means none.
    func recordedName(of name: String, from scope: Scope) -> String? {
        nearestMatch(named: name, from: scope, depth: 0)?.name
    }

    /// `name` qualified by each name a module of the diagram can be written by: `ModA.Foo` and
    /// `ModB.Foo` for `Foo`.
    func moduleQualifiedNames(of name: String) -> [String] {
        modules.qualifiers.map { "\($0).\(name)" }
    }

    /// The extensions recorded under any of `names`, each with its name, in recording order.
    func extensions(named names: [String]) -> [(name: String, declared: Declared)] {
        let order = { (declared: Declared) in self.recordForDeclaration[declared.declaration]?.order ?? 0 }
        return names.flatMap { name in declarations(named: name).filter(\.isExtension).map { (name, $0) } }
            .sorted { order($0.declared) < order($1.declared) }
    }
}
