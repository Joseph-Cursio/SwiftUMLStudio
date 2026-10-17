import Foundation

/// Follows typealiases for the passes that walk one file at a time: the call graph behind
/// sequence diagrams and the entry-point lists, and the activity diagram's entry finder (#125).
/// After `typealias Alias = Real`, a method declared in `extension Alias` is `Real`'s, and
/// `Alias.make()` calls into `Real`, exactly as if the code had written `Real`.
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
        lookup = LayoutGraphBuilder.TypeLookup(of: items.populateNestedTypes())
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
        guard let lookup else { return name }
        return lookup.resolvedName(of: name, from: DeclarationScope(filePath: file?.path, module: nil))
    }
}
