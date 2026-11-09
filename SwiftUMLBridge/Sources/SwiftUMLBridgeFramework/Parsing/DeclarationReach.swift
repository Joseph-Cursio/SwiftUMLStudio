import SwiftSyntax

// What limits who sees a declaration, as `SyntaxStructureBuilder` reads it from the declaration's
// attributes and place: `@_spi`, `@available` and an `#if` around it.

extension AttributeListSyntax {
    /// Whether these attributes hold `@_spi(...)` (`SyntaxStructure.isSPI`), in any clause of an
    /// `#if` around them too.
    var hasSPI: Bool {
        attributesInEveryClause.contains { $0.attributeName.trimmedDescription == "_spi" }
    }

    /// Whether these attributes hold `@_spi(...)` outside any `#if` (`SyntaxStructure.isSPIInEveryBuild`).
    var hasSPIInEveryBuild: Bool {
        contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.trimmedDescription == "_spi"
        }
    }

    /// Where these attributes make the declaration unavailable (`SyntaxStructure.unavailability`):
    /// in every build, through `@available(*, unavailable)` outside any `#if`; in some builds,
    /// through any `@available` that says `unavailable` or `obsoleted:`, for any platform, or
    /// `@available(swift, introduced:)`, in any clause of an `#if` too.
    var unavailability: AttributeReach {
        let everyBuild = contains { element in
            guard case .attribute(let attribute) = element, let arguments = attribute.availabilityArguments,
                  arguments.first?.argument.trimmedDescription == "*" else { return false }
            return arguments.contains { $0.argument.trimmedDescription == "unavailable" }
        }
        if everyBuild { return .everyBuild }
        let someBuilds = attributesInEveryClause.contains { attribute in
            guard let arguments = attribute.availabilityArguments else { return false }
            let isSwiftVersion = arguments.first?.argument.trimmedDescription == "swift"
            return arguments.contains { argument in
                switch argument.argument {
                case .token(let token):
                    return token.text == "unavailable"
                case .availabilityLabeledArgument(let labeled):
                    return labeled.label.text == "obsoleted" || (isSwiftVersion && labeled.label.text == "introduced")
                default:
                    return false
                }
            }
        }
        return someBuilds ? .someBuilds : .never
    }
}

extension AttributeSyntax {
    /// The arguments of an `@available` attribute; nil for any other.
    var availabilityArguments: AvailabilityArgumentListSyntax? {
        guard attributeName.trimmedDescription == "available",
              case .availability(let arguments)? = self.arguments else { return nil }
        return arguments
    }
}

extension SyntaxProtocol {
    /// Whether this node sits in a clause of an `#if` block, which the parser reads whatever the
    /// condition (`SyntaxStructure.isConditional`).
    var isInIfConfigClause: Bool {
        sequence(first: Syntax(self)) { $0.parent }.contains { $0.is(IfConfigClauseSyntax.self) }
    }
}

extension SyntaxStructure {
    /// Records what limits who sees the declaration `node`, whose attributes are `attributes`:
    /// `@_spi` (`isSPI`, `isSPIInEveryBuild`), an `#if` around it (`isConditional`), and an
    /// `@available` that makes it unavailable (`unavailability`).
    func markReach(of node: some SyntaxProtocol, attributes: AttributeListSyntax) {
        isSPI = attributes.hasSPI
        isSPIInEveryBuild = attributes.hasSPIInEveryBuild
        unavailability = attributes.unavailability
        isConditional = node.isInIfConfigClause
    }
}
