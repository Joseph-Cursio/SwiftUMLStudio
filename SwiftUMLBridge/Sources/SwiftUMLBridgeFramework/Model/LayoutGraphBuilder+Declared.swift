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
        let kind: ElementKind
        let isExtension: Bool
        let scope: Scope
        /// The scope that ranks the declaration among others of its name (`DeclarationScope.nearest`):
        /// for a member, that of the outermost type it belongs to, since `Foo.X` is looked up by
        /// finding `Foo` first. A member an extension adds ranks by `TypeLookup.memberRank`.
        let rankScope: Scope
        /// The most restrictive access level of the declaration and the declarations enclosing
        /// it, with an enclosing extension's modifier applied. `TypeLookup.access(of:)` also caps
        /// it by the type that extension extends.
        let ownAccess: ElementAccessibility
        /// Whether the declaration, a declaration enclosing it, or its enclosing extension is
        /// marked `@_spi(...)` (`SyntaxStructure.isSPI`), so not every file that imports its
        /// module sees it, whatever `ownAccess` says.
        let isSPI: Bool
        /// Whether the declaration, a declaration enclosing it, or its enclosing extension sits in
        /// a clause of an `#if` block (`SyntaxStructure.isConditional`), so a build may drop it.
        let isConditional: Bool
        /// Whether `@_spi(...)` marks the declaration, a declaration enclosing it, or its enclosing
        /// extension in every build (`SyntaxStructure.isSPIInEveryBuild`).
        let isSPIInEveryBuild: Bool
        /// Where an `@available` makes the declaration itself unavailable
        /// (`SyntaxStructure.unavailability`), so an available one of its name may shadow it.
        let unavailability: AttributeReach
        /// The type the enclosing extension extends, as written there, when there is one.
        let extended: ExtensionTarget?
        /// For a typealias, the name of the type it aliases, looked up from its own scope (#125).
        let aliasTarget: String?
        /// For a class, the first type its inheritance clause names, without generic arguments,
        /// looked up from its own scope: its superclass, when that is a class
        /// (`TypeLookup.superclass(of:depth:)`).
        let superclassName: String?
        /// Whether the declaration itself is `private`: a member so declared is seen only inside
        /// the type, and never through a subclass (`TypeLookup.inheritedMember`).
        let isPrivate: Bool
        /// For an extension or a typealias, `SyntaxStructure.isSugared`: its name, or its
        /// `aliasTarget`, is a standard-library type's, whatever the project declares (#126).
        let isSugared: Bool
        /// The module of the outermost type around the declaration, before any extension: its
        /// container's for a member `mergeExtensions` moved into a type of another module.
        let outermostModule: String?
        /// The name of that outermost type: `Foo` for a `V` that `struct Foo` declares, and a
        /// top-level type's own.
        let outermostName: String?
        /// The file of that outermost type: `Foo`'s for a member merged in from an extension, which
        /// `rankScope` need not be (`TypeLookup.memberRank`).
        let outermostFilePath: String?

        /// `container` is the declaration `item` is a member of, when `item.parent` is not set:
        /// a typealias is never flattened out of its type's members. `rankedAs` overrides
        /// `rankScope`.
        init(
            _ item: SyntaxStructure, kind: ElementKind, nodeId: String?, in container: SyntaxStructure? = nil,
            rankedAs: Scope? = nil
        ) {
            self.nodeId = nodeId
            declaration = ObjectIdentifier(item)
            self.kind = kind
            isExtension = kind == .extension
            aliasTarget = kind == .typealias ? item.typename : nil
            superclassName = kind == .class
                ? item.inheritedTypes?.first?.name.map { $0.removeAngleBracketsWithContent() } : nil
            isPrivate = item.accessibility == .private
            isSugared = item.isSugared
            unavailability = item.unavailability
            scope = Scope(of: item, in: container)
            // Extensions are top level, so a chain holds at most one, last.
            let chain = Array(sequence(first: item) { $0 === item ? container ?? $0.parent : $0.parent })
            let declared = chain.prefix { $0.kind != .extension }
            var levels = declared.map { $0.accessibility.flatMap { $0 == .other ? nil : $0 } ?? .internal }
            let enclosingExtension = chain.first { $0.kind == .extension }
            isSPI = declared.contains { $0.isSPI } || enclosingExtension?.isSPI == true
            isSPIInEveryBuild = declared.contains { $0.isSPIInEveryBuild }
                || enclosingExtension?.isSPIInEveryBuild == true
            isConditional = declared.contains { $0.isConditional } || enclosingExtension?.isConditional == true
            if let enclosing = enclosingExtension, !levels.isEmpty,
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
            outermostName = declared.last?.name
            outermostFilePath = declared.last?.sourceLocation?.filePath ?? scope.filePath
            rankScope = rankedAs ?? declared.last.flatMap { $0 === item ? nil : Scope(of: $0) } ?? scope
            extended = chain.first { $0.kind == .extension && $0 !== item }.flatMap { enclosing in
                enclosing.name.map {
                    ExtensionTarget(name: $0, scope: Scope(of: enclosing), isSugared: enclosing.isSugared)
                }
            }
        }
    }
}
