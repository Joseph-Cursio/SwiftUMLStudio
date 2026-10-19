import Foundation
import Synchronization

// MARK: - Lookup Memos

/// What `TypeLookup` keeps once worked out, kept apart so the lookup stays a readable size.
/// Without them, a name many same-named declarations share made every lookup of it redo the
/// lookups each of them depends on, cubic in their number.
extension LayoutGraphBuilder {
    /// The type each declaration's enclosing extension extends, for each depth a lookup asks at
    /// (`TypeLookup.enclosingExtensionType(of:depth:)`). The lookup must stay `Sendable`, for
    /// `TypeAliasResolver.none`, so this is a class behind a lock; the lookup starts a new one
    /// whenever it records a declaration, so a copy of it never shares a stale entry.
    final class EnclosingTypes: Sendable {
        private let typeForDeclaration = Mutex<[ObjectIdentifier: [Int: Declared?]]>([:])

        /// The type for `declaration` at `depth`, from `lookUp` the first time. The lookup runs
        /// outside the lock, since it asks this again for the declarations it walks.
        func type(of declaration: ObjectIdentifier, depth: Int, lookUp: () -> Declared?) -> Declared? {
            if let known = typeForDeclaration.withLock({ $0[declaration]?[depth] }) { return known }
            let type = lookUp()
            typeForDeclaration.withLock { $0[declaration, default: [:]][depth] = .some(type) }
            return type
        }
    }

    /// A name `TypeLookup.typeWithSureKind` looks up for a writer with no candidate in its own
    /// file: the answer then depends on the writer's module, and on its imports for a name read
    /// through a module, alone.
    struct SharedLookupKey: Hashable {
        let name: String
        let root: NameRoot
        let module: String?
        let imports: Set<String>?
        let depth: Int
    }

    /// The type each typealias comes to, and whether its kind is sure, for each depth a lookup
    /// reaches it at (`TypeLookup.typeWithSureKind`), and that lookup's answer for each
    /// `SharedLookupKey`, filled the first time one asks. The depth is part of the key because
    /// the lookup's depth guard can cut an alias chain short, so a type worked out deep in one
    /// chain is not the alias's own. A class, so `EdgeEndIds` can fill it without being
    /// mutating, and kept out of the lookup, which must stay `Sendable`; `EdgeEndIds` starts a new
    /// one whenever it records a declaration.
    final class AliasKinds {
        private var typesForAlias: [ObjectIdentifier: [Int: (type: Declared?, isSure: Bool)]] = [:]
        var shared: [SharedLookupKey: (type: Declared?, kindIsSure: Bool)] = [:]

        subscript(alias: ObjectIdentifier, depth: Int) -> (type: Declared?, isSure: Bool)? {
            get { typesForAlias[alias]?[depth] }
            set { typesForAlias[alias, default: [:]][depth] = newValue }
        }
    }
}
