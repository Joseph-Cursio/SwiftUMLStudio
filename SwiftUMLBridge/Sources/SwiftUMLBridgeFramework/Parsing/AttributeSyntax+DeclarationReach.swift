import SwiftSyntax

// What limits who sees a declaration, as `SyntaxStructureBuilder` reads it from the declaration's
// attributes and place: `@_spi`, `@available` and an `#if` around it.

extension AttributeSyntax {
    /// The arguments of an `@available` attribute; nil for any other.
    var availabilityArguments: AvailabilityArgumentListSyntax? {
        guard attributeName.trimmedDescription == "available",
              case .availability(let arguments)? = self.arguments else { return nil }
        return arguments
    }
}
