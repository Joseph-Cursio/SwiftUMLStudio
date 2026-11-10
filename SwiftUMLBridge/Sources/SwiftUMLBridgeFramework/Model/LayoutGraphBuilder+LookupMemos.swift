import Synchronization

// MARK: - Lookup Memos

/// What `TypeLookup` keeps once worked out, kept apart so the lookup stays a readable size.
/// Without them, a name many same-named declarations share made every lookup of it redo the
/// lookups each of them depends on, cubic in their number.
extension LayoutGraphBuilder {
    /// The type each declaration's enclosing extension extends, for each depth a lookup asks at
    /// (`TypeLookup.enclosingExtensionType(of:depth:)`). The lookup must stay `Sendable`, for
    /// `TypeAliasResolver.withoutProject`, so this is a class behind a lock; the lookup starts a new one
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

    /// The outermost type a declaration belongs to past any extension, by name and file
    /// (`TypeLookup.owningDeclaration(of:depth:)`).
    typealias OwningDeclaration = (name: String?, filePath: String?)

    /// What the names a writer of no known module builds on the types around it take, filled the
    /// first time one asks, while an extension adds one of their candidates and they are fitted by
    /// the whole set (#252): the outermost of those types, as the writer's file reads its name
    /// (`TypeLookup.enclosingOwner(of:depth:)`), and each name's candidates for a scope
    /// (`TypeLookup.enclosingCandidates(_:from:depth:lookUp:)`). Without them, each lookup of such a
    /// name scanned all the types of its name and of the outermost one, so many writers among many
    /// same-named extensions cost the square of their number. With the writer's module known, it
    /// also keeps whether the declaration such a name finds belongs to that outermost type
    /// (`TypeLookup.isMemberOfTypeAround`). A class behind a lock, as `EnclosingTypes` is, which the
    /// lookup starts anew whenever what a name means may change.
    final class EnclosingLookups: Sendable {
        private let ownerForKey = Mutex<[EnclosingOwnerKey: OwningDeclaration?]>([:])
        private let candidatesForKey = Mutex<[EnclosingCandidatesKey: [Declared]]>([:])
        private let isMemberForKey = Mutex<[EnclosingMemberKey: Bool]>([:])

        /// The owner for `key`, from `lookUp` the first time, which runs outside the lock.
        func owner(for key: EnclosingOwnerKey, lookUp: () -> OwningDeclaration?) -> OwningDeclaration? {
            if let known = ownerForKey.withLock({ $0[key] }) { return known }
            let owner = lookUp()
            ownerForKey.withLock { $0[key] = .some(owner) }
            return owner
        }

        /// The candidates for `key`, from `lookUp` the first time, which runs outside the lock.
        func candidates(for key: EnclosingCandidatesKey, lookUp: () -> [Declared]) -> [Declared] {
            if let known = candidatesForKey.withLock({ $0[key] }) { return known }
            let candidates = lookUp()
            candidatesForKey.withLock { $0[key] = candidates }
            return candidates
        }

        /// Whether the declaration `key` found is a member of the type around its writer, from
        /// `lookUp` the first time, which runs outside the lock.
        func isMember(for key: EnclosingMemberKey, lookUp: () -> Bool) -> Bool {
            if let known = isMemberForKey.withLock({ $0[key] }) { return known }
            let isMember = lookUp()
            isMemberForKey.withLock { $0[key] = isMember }
            return isMember
        }
    }

    /// A declaration a name built on the types around a writer finds, where it finds it
    /// (`TypeLookup.isMemberOfTypeAround`): every writer in one extension of a file finds the same
    /// one and shares the answer, which otherwise scans the name's candidates for each of them. The
    /// writer's file stands for its module too, as each file has one.
    struct EnclosingMemberKey: Hashable {
        let place: EnclosingCandidatesKey
        let found: ObjectIdentifier
        let readingModules: Bool
    }

    /// A name built on the types around a writer of no known module, with all of the writer's
    /// scope that its candidates can depend on (`EnclosingLookups`): its file, its imports, the
    /// types around it and the extension they end at, and the lookup's depth. The file is its
    /// path's bytes, as the directory ranking compares them: a string would hold a path's composed
    /// and decomposed spellings equal, and give one directory's writers the other's candidates.
    struct EnclosingCandidatesKey: Hashable {
        let name: String
        let isRecorded: Bool
        let filePath: [UInt8]?
        let imports: Set<String>?
        let enclosingTypes: [String]
        let enclosingExtension: String?
        let isSugared: Bool
        let depth: Int
    }

    /// What `EnclosingLookups` keeps an owner for: the outermost name around a writer, how its file
    /// reads it, and the lookup's depth, which its guards depend on. The file is its path's bytes,
    /// as for `EnclosingCandidatesKey`, since which type the name means can go by its directory.
    struct EnclosingOwnerKey: Hashable {
        let outermost: String
        let isSugared: Bool
        let filePath: [UInt8]?
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

    /// Whether every candidate of a shared lookup comes to a protocol, once a writer has worked
    /// it out (`SharedLookup.everyComesToProtocol`).
    enum ProtocolVerdict { case unknown, every, notEvery }

    /// What the writers of one `SharedLookupKey` share: the candidates, and whether every one comes
    /// to a protocol, each candidate coming to what it does from its own scope. Which candidate a
    /// writer with no module means goes by its directory too (`DeclarationScope.rankingDirectory`),
    /// so the answer is kept per directory, and a writer with a module has the one, under `nil`.
    /// A writer whose own file bears on the name never shares (`TypeLookup.ownFileBears(on:_:)`),
    /// or the others would take what only it can see.
    final class SharedLookup {
        let found: [Declared]
        var everyComesToProtocol = ProtocolVerdict.unknown
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
