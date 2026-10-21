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

    /// The type each dotted name's first component means (`TypeLookup.started(_:from:depth:)`)
    /// for a writer at file scope with no declaration of that name in its own file, where the
    /// answer depends on the writer's module and imports alone, filled the first time one asks.
    /// Without it, every dotted name looked its first component up among all of its same-named
    /// types again. A class behind a lock, as `EnclosingTypes` is, which the lookup starts anew
    /// whenever it records a declaration.
    final class NameStarts: Sendable {
        private let startForKey = Mutex<[NameStartKey: NameStart]>([:])

        /// The start for `key`, from `lookUp` the first time, which runs outside the lock.
        func start(for key: NameStartKey, lookUp: () -> NameStart) -> NameStart {
            if let known = startForKey.withLock({ $0[key] }) { return known }
            let start = lookUp()
            startForKey.withLock { $0[key] = start }
            return start
        }
    }

    /// A first component `NameStarts` keeps the start of, with the writer's module and imports.
    struct NameStartKey: Hashable {
        let first: String
        let module: String?
        let imports: Set<String>?
        let depth: Int
    }

    /// A name `TypeLookup.typeWithSureKind` looks up for a writer with no candidate in its own
    /// file: the answer then depends on the writer's module, its imports, and the type a dotted
    /// name starts at there, alone.
    struct SharedLookupKey: Hashable {
        let name: String
        let root: NameRoot
        let isRecorded: Bool
        let start: NameStart?
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
