import Foundation

/// Format-agnostic scaffolding shared by the PlantUML, Mermaid, and Nomnoml
/// class-diagram emitters. Each emitter supplies only its format-specific text
/// building; the skip/generics/linking flow and the member-eligibility filter
/// live here so they stay in sync across formats.
extension SyntaxStructure {
    /// Run the common emit flow — kind guard, exclusion `skip`, optional generics,
    /// and inheritance linking — delegating the format-specific body to `textBuilder`.
    func renderDiagramText(
        context: DiagramContext,
        textBuilder: (_ kind: ElementKind, _ generics: String?, _ context: DiagramContext) -> String?
    ) -> String? {
        guard let kind else { return nil }
        guard skip(element: self, basedOn: context.configuration) == false else { return nil }

        let generics: String? = context.configuration.elements.showGenerics ? genericsStatement() : nil
        guard let textualRepresentation = textBuilder(kind, generics, context) else {
            return nil
        }
        addLinking(context: context)
        return textualRepresentation
    }

    /// Decide whether `element` (a substructure of `self`) is an eligible member to
    /// render, applying the member-kind and access-level filters from `context`.
    /// Returns the element that should actually be rendered (unwrapping enum cases),
    /// or `nil` when the member should be skipped.
    func renderableMember(from element: SyntaxStructure, context: DiagramContext) -> SyntaxStructure? {
        guard
            element.kind == ElementKind.functionMethodInstance ||
            element.kind == ElementKind.functionMethodStatic ||
            element.kind == ElementKind.varInstance ||
            element.kind == ElementKind.varStatic ||
            element.kind == ElementKind.enumcase else { return nil }

        let actualElement: SyntaxStructure
        if element.kind == ElementKind.enumcase {
            guard let first = element.substructure?.first else { return nil }
            actualElement = first
        } else {
            actualElement = element
        }

        if kind != .extension {
            let generateMembersWithAccessLevel: [ElementAccessibility] = context.configuration.elements
                .showMembersWithAccessLevel.compactMap { ElementAccessibility(orig: $0) }
            let effectiveAccessibility = actualElement.accessibility ?? ElementAccessibility.internal
            if generateMembersWithAccessLevel.contains(effectiveAccessibility) == false {
                return nil
            }
        }
        return actualElement
    }

    /// Whether this element's name matches any of the given exclude glob patterns.
    func isExcluded(byPatterns patterns: [String]?) -> Bool {
        guard let elementName = name, let patterns else { return false }
        return patterns.contains { elementName.isMatching(searchPattern: $0) }
    }
}
