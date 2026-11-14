import SwiftSyntax

// What limits who sees a declaration, as `SyntaxStructureBuilder` reads it from the declaration's
// attributes and place: `@_spi`, `@available` and an `#if` around it.

extension SyntaxProtocol {
    /// Whether this node sits in a clause of an `#if` block, which the parser reads whatever the
    /// condition (`SyntaxStructure.isConditional`).
    var isInIfConfigClause: Bool {
        sequence(first: Syntax(self)) { $0.parent }.contains { $0.is(IfConfigClauseSyntax.self) }
    }
}
