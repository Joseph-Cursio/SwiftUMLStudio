import Foundation

/// Where a declaration lives, for picking among declarations that share a name.
///
/// Class-diagram edges (`LayoutGraphBuilder`) and merged extensions (`mergeExtensions`) both use
/// `nearest(among:scope:)`, so the box an extension's members are merged into is the box its
/// nested types hang off.
struct DeclarationScope {
    let filePath: String?
    let module: String?

    init(of item: SyntaxStructure) {
        filePath = item.sourceLocation?.filePath
        module = item.module
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
