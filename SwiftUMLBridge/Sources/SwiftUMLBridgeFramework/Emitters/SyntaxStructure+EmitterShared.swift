import Foundation

/// Format-agnostic scaffolding shared by the PlantUML, Mermaid, and Nomnoml
/// class-diagram emitters. Each emitter supplies only its format-specific text
/// building; the skip/generics/linking flow and the member-eligibility filter
/// live here so they stay in sync across formats.
extension SyntaxStructure {
    /// Whether a class diagram draws this element: a processable kind the configuration does not
    /// hide. `DiagramScript` reserves ids for exactly these elements, then emits them.
    func isDrawn(in configuration: Configuration) -> Bool {
        guard let kind, ElementKind.processable.contains(kind) else { return false }
        return skip(element: self, basedOn: configuration) == false
    }

    /// Run the common emit flow — kind guard, exclusion `skip`, optional generics,
    /// and inheritance linking — delegating the format-specific body to `textBuilder`.
    func renderDiagramText(
        context: DiagramContext,
        textBuilder: (_ kind: ElementKind, _ generics: String?, _ context: DiagramContext) -> String?
    ) -> String? {
        guard let kind else { return nil }
        guard skip(element: self, basedOn: context.configuration) == false else { return nil }

        let generics: String? = context.elements.showGenerics ? genericsStatement() : nil
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

    /// Whether any of the given exclude glob patterns matches one of this element's `excludeNames`.
    func isExcluded(byPatterns patterns: [String]?) -> Bool {
        guard let patterns else { return false }
        let names = excludeNames
        // Names are read as Swift reads them (#123), so a pattern is too: `` `Base` `` is `Base`.
        return patterns.contains { pattern in
            let searchPattern = pattern.canonicalDottedName
            return names.contains { $0.isMatching(searchPattern: searchPattern) }
        }
    }

    /// The names an exclude pattern matches this element by: its type's name, with and without
    /// the types that contain it. A struct nested in `Outer` is named `Inner`, and
    /// `extension Outer.Inner` is named `Outer.Inner`, so the struct also gives its `fullName` and
    /// the extension its last component: `Inner` and `Outer.Inner` each match both, as `Foo`
    /// matches `struct Foo` and `extension Foo` (#154). A supertype entry has no kind and no
    /// parent, so it gives only its name as written in the inheritance clause.
    var excludeNames: [String] {
        guard let name else { return [] }
        let other = kind == .extension ? displayName : fullName
        guard let other, other != name else { return [name] }
        return [name, other]
    }
}
