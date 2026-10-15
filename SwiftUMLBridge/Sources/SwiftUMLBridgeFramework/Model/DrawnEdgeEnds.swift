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
    }

    /// The drawn element `end` resolves to, or `nil` when it resolves to none.
    func element(at end: LayoutGraphBuilder.EdgeEnd) -> SyntaxStructure? {
        endIds.id(of: end).flatMap { elementForKey[$0] }
    }
}
