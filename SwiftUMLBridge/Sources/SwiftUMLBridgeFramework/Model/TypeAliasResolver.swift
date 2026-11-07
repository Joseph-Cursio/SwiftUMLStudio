import Foundation

/// Follows typealiases for the passes that write a type's name rather than look up its
/// declaration (#125): the call graph behind sequence diagrams and the entry-point lists, the
/// activity diagram's entry finder, the text formats' supertype edges and `deps --types`. After
/// `typealias Alias = Real`, a method declared in `extension Alias` is `Real`'s, `Alias.make()`
/// calls into `Real`, and `struct S: Alias` ends its edge on `Real`, exactly as if the code had
/// written `Real`.
///
/// It is built once from every file, on the lookup class diagrams resolve extensions by
/// (`LayoutGraphBuilder.TypeLookup`), so an alias ranks with the types of its name, and a
/// `private` or `fileprivate` alias names its type only in its own file.
struct TypeAliasResolver {
    private let lookup: LayoutGraphBuilder.TypeLookup?

    /// A resolver that follows nothing, for sources read without their project.
    static let none = TypeAliasResolver(lookup: nil)

    private init(lookup: LayoutGraphBuilder.TypeLookup?) {
        self.lookup = lookup
    }

    /// A resolver for the declarations parsed from every file, `items` being their top-level ones.
    /// Nested types are flattened, setting each one's `parent`, so pass items parsed for this.
    init(items: [SyntaxStructure]) {
        self.init(flattened: items.populateNestedTypes())
    }

    /// A resolver for items whose nested types are already flattened, as class-diagram
    /// preparation leaves them (`preparedForClassDiagram(with:)`); they are not touched.
    init(flattened items: [SyntaxStructure]) {
        lookup = LayoutGraphBuilder.TypeLookup(of: items)
    }

    /// A resolver for `sources`, each the contents of its file. When no source so much as
    /// mentions `typealias`, it follows nothing and parses nothing.
    init(sources: [(file: URL, contents: String)]) {
        guard sources.contains(where: { $0.contents.contains("typealias") }) else {
            self.init(lookup: nil)
            return
        }
        self.init(items: sources.flatMap {
            SyntaxStructure.declarations(in: $0.contents, file: $0.file)?.substructure ?? []
        })
    }

    /// The type name `name` comes to where `file` writes it, once every typealias it goes through
    /// is followed (`TypeLookup.resolvedName(of:from:)`); `name` itself when it names no alias
    /// there. With no `file`, as for an entry point typed in, every file's aliases are seen, and
    /// of same-named ones the first is taken, no directory ranking them.
    func resolve(_ name: String, in file: URL?) -> String {
        resolve(name, from: DeclarationScope(filePath: file?.path, module: nil))
    }

    /// What `name` can come to when it is typed in, as an entry point, with no file to rank from:
    /// what it comes to with no file (`resolve(_:in:)`), then what each declaration of it comes
    /// to, in the order they were read, then `name` itself, each once. A method in
    /// `extension Alias` is filed under whichever type `Alias` means there: what one of those
    /// declarations comes to, or `Alias` itself where none of them is visible. A nested type's
    /// method is filed under its innermost name, so `name` itself also finds that. Each dotted
    /// name is followed by what it comes to once its first part is read as Swift reads it
    /// (`respelled(_:from:)`), so `Svc` after `typealias Svc = O.In` and `typealias O = Real` also
    /// comes to `Real.In`, under which `In`'s own body is filed (#239).
    func entryTypes(of name: String) -> [String] {
        var types: [String] = []
        func add(_ type: String, from scope: DeclarationScope) {
            var spelled = type
            // Each step reads one more first part; a cycle of aliases, which Swift rejects, ends here.
            for _ in 0..<8 {
                if !types.contains(spelled) { types.append(spelled) }
                guard let next = respelled(spelled, from: scope), next != spelled else { return }
                spelled = next
            }
        }
        let anywhere = DeclarationScope(filePath: nil, module: nil)
        add(resolve(name, in: nil), from: anywhere)
        for declared in lookup?.typesForName[name] ?? [] {
            guard let target = declared.aliasTarget else {
                add(name, from: anywhere)
                continue
            }
            if declared.isSugared {
                if !types.contains(target) { types.append(target) }
            } else {
                add(resolve(target, from: declared.scope), from: declared.scope)
            }
        }
        if !types.contains(name) { types.append(name) }
        return types
    }

    /// `name` with its first part read as Swift reads it where `scope` writes it: through the
    /// typealias it names, so `O.In` is `Real.In` after `typealias O = Real`, or, as the writer's
    /// own module (`namesOwnModule(_:before:from:)`), dropped, so `Main.Real` is `Real`; `nil`
    /// when neither changes it, or `name` has one part.
    private func respelled(_ name: String, from scope: DeclarationScope) -> String? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        let first = String(name[..<dot])
        let resolved = resolve(first, from: scope)
        if resolved != first { return resolved + name[dot...] }
        let rest = String(name[name.index(after: dot)...])
        return namesOwnModule(first, before: rest, from: scope) ? rest : nil
    }

    /// Whether `qualifier`, written in `scope` as the first part of a name whose `rest` starts
    /// with a type the project declares, can only be the writer's own module. The commands that
    /// take `--entry` read no package, so no module is known by name (#239), but Swift lets a file
    /// write another module's name only when it imports that module, all of it or a declaration
    /// of it, and reads a name as a type before a module. So a qualifier the file does not import,
    /// that names no type or typealias of the project, is the file's own module. `Swift` needs no
    /// import, and a file whose imports are unknown says nothing.
    private func namesOwnModule(_ qualifier: String, before rest: String, from scope: DeclarationScope) -> Bool {
        guard let lookup, let imports = scope.imports, qualifier != "Swift",
              !imports.contains(qualifier), !imports.contains(where: { $0.hasPrefix("\(qualifier).") })
        else { return false }
        let declares = { (name: String) in lookup.declarations(named: name).contains { !$0.isExtension } }
        return !declares(qualifier) && declares(String(rest.prefix { $0 != "." }))
    }

    /// The type name `name` comes to where a declaration in `scope` writes it in its inheritance
    /// clause: a member of a type around the declaration first, as Swift looks it up
    /// (`TypeLookup.qualifiedName(ofWritten:from:)`, #157), then through every typealias. A module
    /// qualifier is not read: an edge is written to this name only when it ends on no drawn
    /// element (`DiagramContext.addLinking`), so `ModA.Foo` stays as written (#124). A member of
    /// `extension ModA.Foo` is still looked for in ModA's `Foo` first, as `ModA.Foo.Base`.
    func resolve(_ name: String, from scope: DeclarationScope) -> String {
        guard let lookup else { return name }
        let qualified = lookup.qualifiedName(ofWritten: name, from: scope)
        return lookup.resolvedName(of: qualified, from: scope, readingModules: false)
    }

    /// Whether `patterns` exclude the supertype edge to `supertype`, written in `scope`: by the
    /// name as written, as before, or by the type it comes to, so excluding `Proto` also hides
    /// `struct S: Q` after `typealias Q = Proto`, and excluding `Outer.Base` hides `class Near:
    /// Base` in `enum Outer`. A module qualifier is read here (#124), as SVG reads it, so
    /// excluding `Q` hides `struct S: ModA.Q`, and excluding `StoreType` or `Store` hides
    /// `struct S: Lib.StoreType` after Lib's `typealias StoreType = Store`.
    func isExcluded(
        _ supertype: SyntaxStructure, from scope: DeclarationScope, byPatterns patterns: [String]?
    ) -> Bool {
        if supertype.isExcluded(byPatterns: patterns) { return true }
        guard let lookup, patterns?.isEmpty == false, let name = supertype.name?.removeAngleBracketsWithContent() else {
            return false
        }
        let qualified = lookup.qualifiedName(ofWritten: name, from: scope)
        var resolved = [resolve(name, from: scope), lookup.resolvedName(of: qualified, from: scope)]
        if lookup.readsModule(qualified.name, from: scope),
           let recorded = lookup.recordedName(of: qualified.name, from: scope) {
            resolved.append(recorded)
        }
        return resolved.contains { $0 != name && SyntaxStructure(name: $0).isExcluded(byPatterns: patterns) }
    }
}
