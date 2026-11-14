import SwiftSyntax

/// An `#if` block in a type body is one member, and an `#if` around attributes is one element of
/// the attribute list, so a reader that loops over a type's members or a declaration's attributes
/// sees neither what is inside. These read every clause, `#else` and `#elseif` included, as the
/// class diagram and the call graph do: neither the CLI nor Studio knows which conditions hold
/// (#135). Nested `#if` blocks are read too.
extension MemberBlockItemListSyntax {
    /// Each member declaration in source order, with an `#if` block replaced by the members of
    /// all its clauses.
    var declarationsInEveryClause: [DeclSyntax] {
        flatMap { member -> [DeclSyntax] in
            guard let ifConfig = member.decl.as(IfConfigDeclSyntax.self) else { return [member.decl] }
            return ifConfig.clauses.flatMap { clause -> [DeclSyntax] in
                guard case .decls(let members)? = clause.elements else { return [] }
                return members.declarationsInEveryClause
            }
        }
    }
}
