import SwiftParser
import SwiftSyntax
import Testing

/// The extended type of the first extension in `extension <spelling> {}`.
func extendedType(_ spelling: String) throws -> TypeSyntax {
    let file = Parser.parse(source: "extension \(spelling) {}")
    let decl = try #require(file.statements.first?.item.as(ExtensionDeclSyntax.self))
    return decl.extendedType
}
