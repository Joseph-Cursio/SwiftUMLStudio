import Foundation

/// Where a declaration lives, for picking among declarations that share a name.
///
/// Class-diagram edges (`LayoutGraphBuilder`) and merged extensions (`mergeExtensions`) both use
/// `nearest(among:scope:)`, so the box an extension's members are merged into is the box its
/// nested types hang off.
struct DeclarationScope {
    let filePath: String?
    let module: String?
    /// The modules the declaration's file imports; nil when unknown (`SyntaxStructure.imports`).
    let imports: Set<String>?
    /// The full names of the types whose members a name written in the declaration's
    /// inheritance clause sees, innermost first: each type around it, up to and including the
    /// type an enclosing extension extends, which sees no further out. Empty for a top-level
    /// declaration and for an extension, whose clause Swift reads at file scope (#157).
    let enclosingTypes: [String]
    /// The extension `enclosingTypes` ends at, when they reach one, with its name and its
    /// `SyntaxStructure.isSugared`. Its type decides which type those names are members of: for
    /// `extension [Int]`, Swift's `Array`, not a project `Array` (`TypeLookup.enclosingRoot(of:depth:)`).
    let enclosingExtension: (name: String, isSugared: Bool)?

    /// The scope of `item`, a member of `container` when `item.parent` is not set: a typealias
    /// is never flattened out of its type's members.
    init(of item: SyntaxStructure, in container: SyntaxStructure? = nil) {
        filePath = item.sourceLocation?.filePath ?? container?.sourceLocation?.filePath
        module = item.module ?? container?.module
        imports = item.imports ?? container?.imports
        let enclosing = item.kind == .extension ? [] : Self.enclosingTypes(from: container ?? item.parent)
        enclosingTypes = enclosing.compactMap { $0.fullName ?? $0.name }
        enclosingExtension = enclosing.last.flatMap { outermost in
            outermost.kind == .extension ? outermost.name.map { ($0, outermost.isSugared) } : nil
        }
    }

    init(filePath: String?, module: String?, imports: Set<String>? = nil) {
        self.filePath = filePath
        self.module = module
        self.imports = imports
        enclosingTypes = []
        enclosingExtension = nil
    }

    /// This scope's file, module and imports alone: where an extension's own clause is read,
    /// which sees no enclosing types.
    var fileScope: DeclarationScope {
        DeclarationScope(filePath: filePath, module: module, imports: imports)
    }

    /// `context` and the types around it, innermost first, stopping after an extension: its body
    /// sees the members of the type it extends, not of the types around that.
    private static func enclosingTypes(from context: SyntaxStructure?) -> [SyntaxStructure] {
        var types: [SyntaxStructure] = []
        var current = context
        while let type = current, (type.fullName ?? type.name) != nil {
            types.append(type)
            if type.kind == .extension { break }
            current = type.parent
        }
        return types
    }

    /// The candidate a name means where this scope writes it, close to how Swift looks it up: the
    /// first declared in the same file, then in the same module, one ranked in a file before one
    /// ranked in none; for a scope of no known module, as for sources read without their package,
    /// the one nearest by directory (`nearestByDirectory(among:scope:)`), a guess at the module;
    /// then the first of all. `nil` only when there are no candidates. A typealias ModB's
    /// extension adds to ModA's `Foo` ranks in ModB and no file (`TypeLookup.memberRank`), so in
    /// ModB, ModB's own `Foo.X` still comes first, whichever was recorded first: there, `Foo` is
    /// ModB's own `Foo`.
    func nearest<Candidate>(
        among candidates: [Candidate], scope: (Candidate) -> DeclarationScope
    ) -> Candidate? {
        guard let first = candidates.first else { return nil }
        if let filePath, let local = candidates.first(where: { scope($0).filePath == filePath }) {
            return local
        }
        if let module {
            var fileless: Candidate?
            for candidate in candidates {
                let candidateScope = scope(candidate)
                guard candidateScope.module == module else { continue }
                if candidateScope.filePath != nil { return candidate }
                if fileless == nil { fileless = candidate }
            }
            if let fileless { return fileless }
        } else if let near = nearestByDirectory(among: candidates, scope: scope) {
            return near
        }
        return first
    }

    /// The first of `candidates` whose file shares the most leading directories with this scope's,
    /// or `nil` when none shares any. Separate targets and packages are separate directory trees,
    /// so this stands in for the module the sources were read without. A shorter run never wins
    /// and a tie goes to the first, so a directory every candidate is under, the scan's root or
    /// `/`, decides nothing, with no need to know where the scan began. Directories are compared
    /// whole and as spelled, so `Sources/Foo` shares only `Sources` with `Sources/FooBar`, a relative
    /// path shares nothing with an absolute one, and two spellings of one directory, as through a
    /// symlink, share only what they spell alike. It reads paths alone and calls nothing on the
    /// lookup, so it adds no recursion. A name can have thousands of candidates, so it compares
    /// bytes: `hasPrefix` or splitting the paths took seconds.
    private func nearestByDirectory<Candidate>(
        among candidates: [Candidate], scope: (Candidate) -> DeclarationScope
    ) -> Candidate? {
        guard candidates.count > 1, var writer = filePath else { return nil }
        return writer.withUTF8 { writerBytes in
            // Each leading run of directories' length, with its final `/`; the root, however many
            // slashes spell it, is none.
            let start = writerBytes.firstIndex { $0 != Self.slash } ?? writerBytes.endIndex
            let lengths = writerBytes[start...].indices.filter { writerBytes[$0] == Self.slash }.map { $0 + 1 }
            var shared = 0
            var near: Candidate?
            for candidate in candidates {
                guard shared < lengths.count else { break }
                guard var path = scope(candidate).filePath else { continue }
                path.withUTF8 { bytes in
                    while shared < lengths.count, bytes.count >= lengths[shared],
                          memcmp(writerBytes.baseAddress, bytes.baseAddress, lengths[shared]) == 0 {
                        shared += 1
                        near = candidate
                    }
                }
            }
            return near
        }
    }

    /// What `nearest(among:scope:)` goes by in this scope's file beyond its module and imports,
    /// when that file holds no candidate: its directory, and with a module, nothing. In bytes, as
    /// the ranking compares it: a string would hold a name's composed and decomposed spellings
    /// equal, and a memo keyed by it would give one the other's answer.
    var rankingDirectory: [UInt8]? {
        guard module == nil, let filePath else { return nil }
        let bytes = filePath.utf8
        return Array(bytes[..<(bytes.lastIndex(of: Self.slash) ?? bytes.startIndex)])
    }

    private static let slash = UInt8(ascii: "/")
}
