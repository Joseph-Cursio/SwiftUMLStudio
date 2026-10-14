import Foundation

/// Where PlantUML and Nomnoml end the edge of a drawn nested type whose parent the class diagram
/// does not draw. It is found as SVG finds it (`LayoutGraphBuilder.EdgeEndIds`), so the formats
/// agree on which box a hidden type's children hang off.
enum HiddenParentEnd {
    /// A drawn element: an extension that stands in for the hidden type, or the type a hidden
    /// extension extends.
    case element(SyntaxStructure)
    /// No drawn element is the parent, and none declares its qualified name, so the edge names
    /// it: PlantUML and Nomnoml draw that name as a node of its own (#67).
    case undeclared(String)

    /// The end of each drawn nested type in `drawn` whose `nestingParent` is not drawn, among the
    /// `prepared` items the diagram was built from. A nested type left out gets no edge: SVG
    /// finds no drawn element for its parent, and a drawn element already declares the parent's
    /// qualified name, so naming it would hang the type off that unrelated element.
    static func ends(
        of drawn: [SyntaxStructure], among prepared: [SyntaxStructure],
        declaringIdentifier declares: (SyntaxStructure) -> Bool
    ) -> [ObjectIdentifier: HiddenParentEnd] {
        let drawnItems = Set(drawn)
        var endIds = LayoutGraphBuilder.EdgeEndIds()
        // `EdgeEndIds` ends an edge on a node id; no alias exists yet, so each drawn item's index
        // in `prepared` stands in for its id.
        var elementForKey: [String: SyntaxStructure] = [:]
        var declaredNames: Set<String> = []
        for (index, item) in prepared.enumerated() {
            guard let kind = item.kind, ElementKind.processable.contains(kind),
                  let name = item.fullName ?? item.name else { continue }
            let entry = LayoutGraphBuilder.DiagramItem(
                item: item, kind: kind, name: name, isDrawn: drawnItems.contains(item)
            )
            guard entry.isDrawn else {
                endIds.recordHidden(entry)
                continue
            }
            endIds.record(String(index), for: entry)
            elementForKey[String(index)] = item
            // The first of a name keeps it as its alias.
            if declares(item) { declaredNames.insert(name) }
        }

        var ends: [ObjectIdentifier: HiddenParentEnd] = [:]
        for item in drawn {
            guard let parent = item.nestingParent, !drawnItems.contains(parent),
                  let parentName = parent.fullName else { continue }
            let scope = DeclarationScope(of: parent)
            let end: LayoutGraphBuilder.EdgeEnd = parent.kind == .extension
                ? .extended(ObjectIdentifier(parent), name: parentName, scope: scope)
                : .declaration(ObjectIdentifier(parent), name: parentName, scope: scope)
            if let key = endIds.id(of: end), let element = elementForKey[key] {
                ends[ObjectIdentifier(item)] = .element(element)
            } else if !declaredNames.contains(parentName) {
                ends[ObjectIdentifier(item)] = .undeclared(parentName)
            }
        }
        return ends
    }
}
