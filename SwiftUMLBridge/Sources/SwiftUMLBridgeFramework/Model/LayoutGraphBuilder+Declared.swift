import Foundation

// MARK: - Declarations

/// What `TypeLookup` knows of each declaration it records, kept apart so the lookup stays a
/// readable size.
extension LayoutGraphBuilder {
    /// A declaration, as `TypeLookup` needs it to choose among same-named types. A class, since
    /// every lookup filters and passes them along: a copy of the struct it was retained each of
    /// its strings, its two scopes and their imports.
    final class Declared: Sendable {
        /// `nil` for a type the diagram hides: it has no node, but still takes its name's lookup.
        let nodeId: String?
        let declaration: ObjectIdentifier
        let isExtension: Bool
        let scope: Scope
        /// The scope that ranks the declaration among others of its name (`DeclarationScope.nearest`):
        /// for a member, that of the outermost type it belongs to, since `Foo.X` is looked up by
        /// finding `Foo` first. A typealias that `mergeExtensions` moved into ModA's `Foo` from
        /// ModB's `extension ModA.Foo` ranks as ModA's, not as the file it was written in.
        let rankScope: Scope
        /// The most restrictive access level of the declaration and the declarations enclosing
        /// it, with an enclosing extension's modifier applied. `TypeLookup.access(of:)` also caps
        /// it by the type that extension extends.
        let ownAccess: ElementAccessibility
        /// The type the enclosing extension extends, as written there, when there is one.
        let extended: (name: String, scope: Scope)?
        /// For a typealias, the name of the type it aliases, looked up from its own scope (#125).
        let aliasTarget: String?
        /// The module of the outermost type around the declaration, before any extension: its
        /// container's for a member `mergeExtensions` moved into a type of another module.
        let outermostModule: String?

        /// `container` is the declaration `item` is a member of, when `item.parent` is not set:
        /// a typealias is never flattened out of its type's members. `rankedAs` overrides
        /// `rankScope`.
        init(
            _ item: SyntaxStructure, kind: ElementKind, nodeId: String?, in container: SyntaxStructure? = nil,
            rankedAs: Scope? = nil
        ) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(item)
            isExtension = kind == .extension
            aliasTarget = kind == .typealias ? item.typename : nil
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
            outermostModule = declared.last?.module ?? scope.module
            rankScope = rankedAs ?? declared.last.flatMap { $0 === item ? nil : Scope(of: $0) } ?? scope
            extended = chain.first { $0.kind == .extension && $0 !== item }
                .flatMap { enclosing in enclosing.name.map { ($0, Scope(of: enclosing)) } }
        }
    }
}
