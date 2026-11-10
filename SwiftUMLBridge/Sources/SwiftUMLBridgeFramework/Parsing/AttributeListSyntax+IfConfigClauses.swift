import SwiftSyntax

extension AttributeListSyntax {
    /// Each attribute in source order, with an `#if` around attributes replaced by the attributes
    /// of all its clauses.
    var attributesInEveryClause: [AttributeSyntax] {
        flatMap { element -> [AttributeSyntax] in
            switch element {
            case .attribute(let attribute):
                return [attribute]

            case .ifConfigDecl(let ifConfig):
                return ifConfig.clauses.flatMap { clause -> [AttributeSyntax] in
                    guard case .attributes(let attributes)? = clause.elements else { return [] }
                    return attributes.attributesInEveryClause
                }
            }
        }
    }

    /// Each attribute that `matches` and is the first that does under some choice of clauses, in
    /// source order. Without `#if` that is the first match alone. With
    /// `#if A @Attribute(.spotlight) #else @Attribute(.unique) #endif @Attribute(.externalStorage)`
    /// it is the first two: whichever clause is built, its attribute comes first, so the third is
    /// never read. A macro such as `@Model` reads only the first attribute of a name, so a reader
    /// that follows it reads these.
    func firstAttributesInEveryClause(where matches: (AttributeSyntax) -> Bool) -> [AttributeSyntax] {
        firstAttributes(where: matches).attributes
    }

    /// The attributes `firstAttributesInEveryClause` returns, and whether one is found under every
    /// choice of clauses, so that nothing after this list can be first.
    private func firstAttributes(
        where matches: (AttributeSyntax) -> Bool
    ) -> (attributes: [AttributeSyntax], always: Bool) {
        var found: [AttributeSyntax] = []
        for element in self {
            switch element {
            case .attribute(let attribute):
                if matches(attribute) { return (found + [attribute], true) }

            case .ifConfigDecl(let ifConfig):
                // Only an `#else` makes the clauses cover every build.
                var always = ifConfig.clauses.contains { $0.poundKeyword.tokenKind == .poundElse }
                for clause in ifConfig.clauses {
                    guard case .attributes(let attributes)? = clause.elements else {
                        always = false
                        continue
                    }
                    let nested = attributes.firstAttributes(where: matches)
                    found += nested.attributes
                    always = always && nested.always
                }
                if always { return (found, true) }
            }
        }
        return (found, false)
    }
}
