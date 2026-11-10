import Foundation

/// The drawn elements PlantUML, Mermaid and Nomnoml end an edge on, found as SVG finds them
/// (`LayoutGraphBuilder.EdgeEndIds`), so the formats agree on which box an edge reaches: the
/// type a name means where it is written, drawn or hidden, as Swift's access control allows.
struct DrawnEdgeEnds {
    private var endIds = LayoutGraphBuilder.EdgeEndIds()
    /// `EdgeEndIds` ends an edge on a node id; no alias exists yet, so each drawn item's index in
    /// `prepared` stands in for its id.
    private var elementForKey: [String: SyntaxStructure] = [:]

    /// The ends among the `prepared` items a class diagram was built from, of which it draws `drawn`.
    init(drawing drawn: Set<SyntaxStructure>, among prepared: [SyntaxStructure]) {
        for (index, item) in prepared.enumerated() {
            guard let kind = item.kind, ElementKind.processable.contains(kind),
                  let name = item.fullName ?? item.name else { continue }
            let entry = LayoutGraphBuilder.DiagramItem(
                item: item, kind: kind, name: name, isDrawn: drawn.contains(item)
            )
            guard entry.isDrawn else {
                endIds.recordHidden(entry)
                continue
            }
            endIds.record(String(index), for: entry)
            elementForKey[String(index)] = item
        }
        endIds.recordAliases(in: prepared)
    }

    /// The drawn element `end` resolves to, or `nil` when it resolves to none.
    func element(at end: LayoutGraphBuilder.EdgeEnd) -> SyntaxStructure? {
        endIds.id(of: end).flatMap { elementForKey[$0] }
    }

    /// The drawn element an edge to the supertype written `name` in `scope` ends on, and whether
    /// the edge is a realization, the type the name means, drawn or hidden, being a protocol: a
    /// hidden protocol's edge is one even where it ends on its stand-in
    /// (`EdgeEndIds.supertype(named:from:)`).
    func supertype(
        named name: String, from scope: DeclarationScope
    ) -> (element: SyntaxStructure?, isProtocol: Bool) {
        let end = endIds.supertype(named: name, from: scope)
        return (end.id.flatMap { elementForKey[$0] }, end.isProtocol)
    }

    /// The drawn type the drawn extension `anExtension` extends: the one its name means where it
    /// is written, as `mergeExtensions` merges it into (#107). `nil` when that type is hidden, or
    /// when no type of the name is visible there, as for an extension of `String`, or of `[Int]`
    /// beside a project's own `Array` (#126).
    func extendedType(of anExtension: SyntaxStructure) -> SyntaxStructure? {
        guard let name = anExtension.fullName else { return nil }
        let end = LayoutGraphBuilder.EdgeEnd.extended(
            ObjectIdentifier(anExtension), name: name, scope: DeclarationScope(of: anExtension),
            isSugared: anExtension.isSugared
        )
        // When its type is hidden or outside the diagram, a drawn extension stands for that type
        // and so resolves to itself.
        guard let type = element(at: end), type.kind != .extension else { return nil }
        return type
    }
}
