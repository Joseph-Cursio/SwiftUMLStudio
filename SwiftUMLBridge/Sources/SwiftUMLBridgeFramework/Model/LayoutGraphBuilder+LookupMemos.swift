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
    /// answer depends on the writer's module and imports alone, filled the first time one asks: a
    /// name's start is worked out only with a module, and a directory ranks only without one.
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

    /// A name `TypeLookup.typeWithSureKind` looks up for a writer whose own file does not bear on
    /// it (`TypeLookup.ownFileBears(on:_:)`): its candidates then depend on the writer's module, its
    /// imports, and the type a dotted name starts at there, alone (`SharedLookup`).
    struct SharedLookupKey: Hashable {
        let name: String
        let root: NameRoot
        let isRecorded: Bool
        let start: NameStart?
        let module: String?
        let imports: Set<String>?
        let depth: Int
    }

    /// What the writers of one `SharedLookupKey` share: the candidates, and whether every one comes
    /// to a protocol, each candidate coming to what it does from its own scope. Which candidate a
    /// writer with no module means goes by its directory too (`DeclarationScope.rankingDirectory`),
    /// so the answer is kept per directory, and a writer with a module has the one, under `nil`.
    /// A writer whose own file bears on the name never shares (`TypeLookup.ownFileBears(on:_:)`),
    /// or the others would take what only it can see.
    final class SharedLookup {
        let found: [Declared]
        var everyComesToProtocol: Bool?
        var answerInDirectory: [[UInt8]?: (type: Declared?, kindIsSure: Bool)] = [:]

        init(found: [Declared]) {
            self.found = found
        }
    }

    /// The type each typealias comes to, and whether its kind is sure, for each depth a lookup
    /// reaches it at (`TypeLookup.typeWithSureKind`), and what that lookup shares for each
    /// `SharedLookupKey`, filled the first time one asks. The depth is part of the key because
    /// the lookup's depth guard can cut short a lookup made inside a step of an alias chain, as
    /// of the target's name, so a type worked out deep is not the alias's own; the chain itself
    /// keeps its depth (`AliasChain`). A class, so `EdgeEndIds` can fill it without being
    /// mutating, and kept out of the lookup, which must stay `Sendable`; `EdgeEndIds` starts a new
    /// one whenever it records a declaration.
    final class AliasKinds {
        private var typesForAlias: [ObjectIdentifier: [Int: (type: Declared?, isSure: Bool)]] = [:]
        var shared: [SharedLookupKey: SharedLookup] = [:]

        subscript(alias: ObjectIdentifier, depth: Int) -> (type: Declared?, isSure: Bool)? {
            get { typesForAlias[alias]?[depth] }
            set { typesForAlias[alias, default: [:]][depth] = newValue }
        }
    }
}
