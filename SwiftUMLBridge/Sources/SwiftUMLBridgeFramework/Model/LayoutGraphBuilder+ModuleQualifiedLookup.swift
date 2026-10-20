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
    /// (`ModuleQualifiers`), so a `Foo.Inner` another module adds to ModA's `Foo` counts. As in
    /// Swift, the file must import that module or be in it, and a type named like the qualifier
    /// comes first: this runs only when the full name means nothing — `Networking.Request` stays
    /// the type nested in an `enum Networking` — and not when such a type is in scope (`shadows`).
    func moduleMatch(named name: String, from scope: Scope, depth: Int) -> Match? {
        guard let dot = name.firstIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
        let qualifier = String(name[..<dot])
        let named = modules.modules(namedBy: qualifier)
        let rest = String(name[name.index(after: dot)...])
        let declared = named.isEmpty ? [] : declarations(named: rest).filter { !$0.isExtension }
        guard !declared.isEmpty, canName(qualifier, modules: named, from: scope),
              !shadows(qualifier, from: scope, depth: depth) else {
            return nil
        }
        let candidates = declared.filter {
            isVisible($0, from: scope, depth: depth) && owningModule(of: $0, depth: depth).map(named.contains) == true
        }
        return scope.nearest(among: candidates, scope: \.rankScope).map { Match(declared: $0, name: rest) }
    }

    /// Whether a file in `scope` can write `qualifier` for one of `modules`: the file is in that
    /// module or imports it. With the file's imports unknown, it can.
    private func canName(_ qualifier: String, modules named: Set<String>, from scope: Scope) -> Bool {
        guard let imports = scope.imports else { return true }
        return imports.contains(qualifier) || scope.module.map(named.contains) == true
    }

    /// Whether a type or typealias named `qualifier`, visible from `scope`, keeps it from being
    /// read as a module, as Swift reads a type first: one in the file's own module, or in a module
    /// the file imports — so a namespace `enum Analytics` in a module the file does not import
    /// leaves `Analytics.Event` to the module Analytics. With the imports unknown, any does.
    private func shadows(_ qualifier: String, from scope: Scope, depth: Int) -> Bool {
        declarations(named: qualifier).contains { declared in
            guard !declared.isExtension else { return false }
            if let imports = scope.imports, let module = declared.scope.module, module != scope.module,
               !imports.contains(module), !imports.contains(ModuleQualifiers.c99Name(of: module)) {
                return false
            }
            return isVisible(declared, from: scope, depth: depth)
        }
    }

    /// Whether `name`, written in `scope`, means a type only once its first component is read as
    /// a module: `ModA.Foo`, but not `Foo`, nor `Outer.Inner` for a nested type. A name that
    /// cannot be read so (`mayReadModule`) is answered without a lookup.
    func readsModule(_ name: String, from scope: Scope) -> Bool {
        guard mayReadModule(name) else { return false }
        return nearestMatch(named: name, from: scope, depth: 0, readingModules: false) == nil
            && moduleMatch(named: name, from: scope, depth: 0) != nil
    }

    /// Whether `name`, written in `scope`, spells a typealias through its module, as
    /// `extension MyModule.Describable` does after `typealias Describable = CustomStringConvertible`
    /// in MyModule: an extension of the type the alias comes to, as `extension Describable` is.
    /// A name whose rest no typealias is recorded under is answered without a lookup.
    func spellsTypealiasThroughModule(_ name: String, from scope: Scope) -> Bool {
        guard let dot = name.firstIndex(of: "."), namesTypealias(String(name[name.index(after: dot)...]))
        else { return false }
        return readsModule(name, from: scope)
    }

    /// Whether `name`'s first component names a module of the diagram and some type is recorded
    /// under the rest of it: a dictionary check, before any lookup.
    func mayReadModule(_ name: String) -> Bool {
        guard let dot = name.firstIndex(of: "."), !modules.modules(namedBy: String(name[..<dot])).isEmpty else {
            return false
        }
        return declarations(named: String(name[name.index(after: dot)...])).contains { !$0.isExtension }
    }

    /// The module of the outermost type `declared` belongs to: its own, or for a declaration
    /// in an extension, that of the type the extension extends, as the extension finds it.
    func owningModule(of declared: Declared, depth: Int) -> String? {
        guard let extended = declared.extended else { return declared.outermostModule }
        guard depth < 8, let type = extendedType(
            named: extended.name, from: extended.scope, isSugared: extended.isSugared, depth: depth + 1
        ) else {
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
