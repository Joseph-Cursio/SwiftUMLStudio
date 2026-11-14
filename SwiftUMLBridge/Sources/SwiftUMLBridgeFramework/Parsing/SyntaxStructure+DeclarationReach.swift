import SwiftSyntax

// What limits who sees a declaration, as `SyntaxStructureBuilder` reads it from the declaration's
// attributes and place: `@_spi`, `@available` and an `#if` around it.

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
