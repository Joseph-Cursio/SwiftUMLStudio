import SwiftParser
import SwiftSyntax

extension TokenSyntax {
    /// The name as Swift reads it: `` `Plain` `` is `Plain`, one identifier spelt two ways. A name
    /// that needs its backticks wherever it is written keeps them, so it still matches itself: a
    /// raw identifier (`` `Foo Bar` ``) or a keyword (`` `default` ``). Names read as written kept
    /// `` extension `Plain` `` apart from `struct Plain`, and a call to `` `Plain`.make() `` apart
    /// from the method it calls (#123).
    var canonicalName: String {
        guard let name = identifier?.name, name != text,
              name.isValidSwiftIdentifier(for: .variableName) else { return text }
        return name
    }
}

extension SyntaxProtocol {
    /// `trimmedDescription`, with each identifier in it written as its `canonicalName`:
    /// `` [`Pet`] `` is `[Pet]`, and `` [`Foo Bar`] `` stays as it is.
    var canonicalDescription: String {
        let text = trimmedDescription
        guard text.contains("`") else { return text }
        return CanonicalNameRewriter(viewMode: .sourceAccurate).rewrite(self).trimmedDescription
    }
}

extension String {
    /// This identifier as Swift reads it, as `TokenSyntax.canonicalName` gives it for a name typed
    /// in rather than parsed, such as the halves of an `--entry` `Type.method`.
    var canonicalIdentifier: String {
        guard count > 2, hasPrefix("`"), hasSuffix("`") else { return self }
        let name = String(dropFirst().dropLast())
        return !name.contains("`") && name.isValidSwiftIdentifier(for: .variableName) ? name : self
    }
}

/// Writes each identifier token as its `canonicalName`, leaving its trivia alone.
private final class CanonicalNameRewriter: SyntaxRewriter {
    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        let name = token.canonicalName
        return name == token.text ? token : token.with(\.tokenKind, .identifier(name))
    }
}
