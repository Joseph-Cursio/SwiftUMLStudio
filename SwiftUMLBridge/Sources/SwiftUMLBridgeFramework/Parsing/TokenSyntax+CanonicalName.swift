import SwiftParser
import SwiftSyntax

extension TokenSyntax {
    /// The name as Swift reads it: `` `Plain` `` is `Plain`, one identifier spelt two ways. A name
    /// that needs its backticks wherever it is written keeps them, so it still matches itself: a
    /// raw identifier (`` `Foo Bar` ``) or a keyword (`` `default` ``). Names read as written kept
    /// `` extension `Plain` `` apart from `struct Plain`, and a call to `` `Plain`.make() `` apart
    /// from the method it calls (#123). `` `Type` `` and `` `Protocol` `` keep theirs too: a type
    /// member must be written so, and bare, after a `.`, either means a metatype.
    var canonicalName: String {
        guard let name = identifier?.name, name != text, name.isUnescapable else { return text }
        return name
    }

    /// `canonicalName`, but as an expression reads the name: there `` `self` `` and `` `Self` ``
    /// are `self` and `Self`, whose backticks `canonicalName` keeps, as a declaration needs them.
    var expressionName: String {
        if let name = identifier?.name, name == "self" || name == "Self" { return name }
        return canonicalName
    }
}

extension SyntaxProtocol {
    /// `trimmedDescription`, with each identifier in it written as its `canonicalName`:
    /// `` [`Pet`] `` is `[Pet]`, and `` [`Foo Bar`] `` stays as it is. A comment after the node on
    /// its line, or on the lines above it, is not part of it: `var tag: String // note` is a
    /// `String` (#128).
    var canonicalDescription: String {
        let text = trimmedDescription
        guard text.contains("`") else { return text }
        // Detached, so the rewriter does not rebuild the whole tree above the node for each name.
        return CanonicalNameRewriter(viewMode: .sourceAccurate).rewrite(self, detach: true).trimmedDescription
    }

    /// `canonicalDescription`, read as if written on one line: `Swift` then `.Equatable` on the
    /// next line is `Swift.Equatable`, and `Generic<` / `Int` / `>` is `Generic<Int>` (#155); the
    /// receiver of `Store` / `.shared` / `.load()` is `Store.shared` (#133). Where
    /// the trivia between two tokens breaks the line, it is dropped after `.`, `(`, `[` or `<` and
    /// before `.`, `)`, `]`, `>` or `,`, and is one space elsewhere, so `Equatable` / `& Sendable`
    /// is `Equatable & Sendable`. A comment in that trivia goes with it. Trivia within a line is
    /// kept, so text written on one line reads as `canonicalDescription` does.
    var singleLineDescription: String {
        guard trimmedDescription.contains(where: \.isNewline) else { return canonicalDescription }
        let joinsAfter: Set<TokenKind> = [.period, .leftParen, .leftSquare, .leftAngle]
        let joinsBefore: Set<TokenKind> = [.period, .rightParen, .rightSquare, .rightAngle, .comma]
        var text = ""
        var previous: TokenSyntax?
        for token in tokens(viewMode: .sourceAccurate) {
            if let previous {
                // A block comment can break the line too, so look at the text, not the pieces.
                let between = (previous.trailingTrivia + token.leadingTrivia).description
                if !between.contains(where: \.isNewline) {
                    text += between
                } else if !joinsAfter.contains(previous.tokenKind), !joinsBefore.contains(token.tokenKind) {
                    text += " "
                }
            }
            text += token.canonicalName
            previous = token
        }
        return text
    }
}

extension String {
    /// This identifier as Swift reads it, as `TokenSyntax.canonicalName` gives it for a name typed
    /// in rather than parsed, such as the halves of an `--entry` `Type.method`.
    var canonicalIdentifier: String {
        guard count > 2, hasPrefix("`"), hasSuffix("`") else { return self }
        let name = String(dropFirst().dropLast())
        return !name.contains("`") && name.isUnescapable ? name : self
    }

    /// This type, as SourceKit's `key.typename` writes it, read as `singleLineDescription` reads
    /// a parsed one: SourceKit gives the text as written, line breaks and all (#155).
    var singleLineTypeName: String {
        guard contains(where: \.isNewline) else { return self }
        var parser = Parser(self)
        return TypeSyntax.parse(from: &parser).singleLineDescription
    }

    /// Whether this name reads the same without backticks wherever it is written: not a raw
    /// identifier or a keyword, nor `Type` or `Protocol`, which a type member must escape.
    fileprivate var isUnescapable: Bool {
        self != "Type" && self != "Protocol" && isValidSwiftIdentifier(for: .variableName)
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
        return name == token.text ? token : token.detached.with(\.tokenKind, .identifier(name))
    }
}
