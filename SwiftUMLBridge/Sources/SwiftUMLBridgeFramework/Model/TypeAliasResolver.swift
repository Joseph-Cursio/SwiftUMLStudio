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
    /// there. With no `file`, as for an entry point typed in, every file's aliases are seen.
    func resolve(_ name: String, in file: URL?) -> String {
        resolve(name, from: DeclarationScope(filePath: file?.path, module: nil))
    }

    /// The type name `name` comes to where a declaration in `scope` writes it in its inheritance
    /// clause: a member of a type around the declaration first, as Swift looks it up
    /// (`TypeLookup.qualifiedName(ofWritten:from:)`, #157), then through every typealias. A module
    /// qualifier is not read: the name ends an edge on the first box of that name, which for a
    /// bare `Foo` could be another module's `Foo`, so `ModA.Foo` stays as written (#124).
    func resolve(_ name: String, from scope: DeclarationScope) -> String {
        guard let lookup else { return name }
        let qualified = lookup.qualifiedName(ofWritten: name, from: scope, readingModules: false)
        return lookup.resolvedName(of: qualified, from: scope, readingModules: false)
    }

    /// Whether `patterns` exclude the supertype edge to `supertype`, written in `scope`: by the
    /// name as written, as before, or by the type it comes to, so excluding `Proto` also hides
    /// `struct S: Q` after `typealias Q = Proto`, excluding `Outer.Base` hides `class Near:
    /// Base` in `enum Outer`, and excluding `Q` hides `extension ModA.Foo: ModA.Q` (#124).
    func isExcluded(
        _ supertype: SyntaxStructure, from scope: DeclarationScope, byPatterns patterns: [String]?
    ) -> Bool {
        if supertype.isExcluded(byPatterns: patterns) { return true }
        guard let lookup, patterns != nil, let name = supertype.name?.removeAngleBracketsWithContent() else {
            return false
        }
        let resolved = [
            resolve(name, from: scope),
            lookup.resolvedName(of: lookup.qualifiedName(ofWritten: name, from: scope), from: scope)
        ]
        return resolved.contains { $0 != name && SyntaxStructure(name: $0).isExcluded(byPatterns: patterns) }
    }
}
