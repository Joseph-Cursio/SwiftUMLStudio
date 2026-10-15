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

    /// `description` trimmed of whitespace, with each identifier in it written as its
    /// `canonicalName`. Unlike `canonicalDescription`, it keeps a comment beside the node, as the
    /// readers that trimmed `description` themselves always have, so on source with no needless
    /// backticks they read exactly what they read before.
    var canonicalTrimmedText: String {
        var text = description
        if text.contains("`") {
            text = CanonicalNameRewriter(viewMode: .sourceAccurate).rewrite(self).description
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// This dotted name, typed in as `--entry`'s type or `--state`'s `Host.Enum`, with each
    /// component as Swift reads it: `` `Outer`.Inner `` is `Outer.Inner`.
    var canonicalDottedName: String {
        split(separator: ".", omittingEmptySubsequences: false).map { String($0).canonicalIdentifier }
            .joined(separator: ".")
    }
}

/// Writes each identifier token as its `canonicalName`, leaving its trivia alone.
private final class CanonicalNameRewriter: SyntaxRewriter {
    override func visit(_ token: TokenSyntax) -> TokenSyntax {
        let name = token.canonicalName
        return name == token.text ? token : token.with(\.tokenKind, .identifier(name))
    }
}
