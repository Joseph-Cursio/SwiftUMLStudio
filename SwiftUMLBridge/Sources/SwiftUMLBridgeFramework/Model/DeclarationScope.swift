import Foundation

/// Where a declaration lives, for picking among declarations that share a name.
///
/// Class-diagram edges (`LayoutGraphBuilder`) and merged extensions (`mergeExtensions`) both use
/// `nearest(among:scope:)`, so the box an extension's members are merged into is the box its
/// nested types hang off.
struct DeclarationScope {
    let filePath: String?
    let module: String?
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
        let enclosing = item.kind == .extension ? [] : Self.enclosingTypes(from: container ?? item.parent)
        enclosingTypes = enclosing.compactMap { $0.fullName ?? $0.name }
        enclosingExtension = enclosing.last.flatMap { outermost in
            outermost.kind == .extension ? outermost.name.map { ($0, outermost.isSugared) } : nil
        }
    }

    init(filePath: String?, module: String?) {
        self.filePath = filePath
        self.module = module
        enclosingTypes = []
        enclosingExtension = nil
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
    /// first declared in the same file, then in the same module, then the first of all; `nil`
    /// only when there are no candidates.
    func nearest<Candidate>(
        among candidates: [Candidate], scope: (Candidate) -> DeclarationScope
    ) -> Candidate? {
        guard let first = candidates.first else { return nil }
        if let filePath, let local = candidates.first(where: { scope($0).filePath == filePath }) {
            return local
        }
        if let module, let sibling = candidates.first(where: { scope($0).module == module }) {
            return sibling
        }
        return first
    }
}
