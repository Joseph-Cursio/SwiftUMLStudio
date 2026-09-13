import Foundation

internal extension String {
    mutating func appendAsNewLine(_ content: String) {
        append("\n\(content)")
    }
}

internal extension String {
    /// Escapes the XML special characters so the value is safe to embed in an SVG/XML text node.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Replaces characters that conflict with nomnoml node syntax (`[`, `]`, `|`, `;`).
    var nomnomlEscaped: String {
        replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: ";", with: ",")
    }
}

internal extension String {
    func removeAngleBracketsWithContent() -> String {
        replacingOccurrences(of: "\\<.*\\>", with: "", options: .regularExpression)
    }

    func getAngleBracketsWithContent() -> String? {
        do {
            let regex = try NSRegularExpression(pattern: "\\<.*\\>")
            let results = regex.matches(in: self, range: NSRange(startIndex..., in: self))
            let result = results.compactMap { Range($0.range, in: self).map { String(self[$0]) } }
            return result.first
        } catch {
            print("invalid regex: \(error.localizedDescription)")
            return nil
        }
    }
}

internal extension String {
    /// Translate this glob pattern into an anchored regular-expression string
    /// (`^…$`): escape regex metacharacters, then expand `?`, `**/`, `**`, and `*`.
    ///
    /// **The escape happens before the anchors are added, and that ordering is the fix.** The
    /// class used to be `[.+(){\|]`, applied to the already-wrapped `^…$`, and it omitted
    /// `}`, `^` and `$` — every one of which is regex-special and glob-literal:
    ///
    /// | glob | old regex | |
    /// | --- | --- | --- |
    /// | `a}b` | `^a}b$` | **invalid** — ICU rejects a bare `}` |
    /// | `a^b` | `^a^b$` | valid, and **can never match**: two start anchors |
    /// | `a$b` | `^a$b$` | valid, and **can never match** |
    ///
    /// Adding them to the class is not enough on its own: applied after the wrap it would escape
    /// the anchors this function exists to add, and `\^…\$` matches a literal caret. So the
    /// escape now runs on `self` and the anchors are added to the escaped result.
    ///
    /// **`[` and `]` are deliberately still not escaped.** They are glob syntax, not accidents —
    /// `pathContainsGlobSyntax` lists `[` as one of the four characters that make a path a glob —
    /// and a glob character class `[abc]` is spelled the same way in a regex, so passing it
    /// through is what makes it work. An *unbalanced* `[` still produces an invalid pattern, and
    /// that is a malformed glob rather than a translation bug; `isMatching` below no longer
    /// treats one as a match.
    ///
    /// Known and unfixed: glob negation is `[!abc]` where regex wants `[^abc]`, so a negated
    /// class is read as a literal `!`. That is a semantic gap, not an invalid pattern, and it is
    /// left for its own change.
    ///
    /// Found by the SwiftInferProperties pipeline walk (subject 2), whose prediction for this
    /// function was written before the tool ran and named `[` — and explicitly guessed that `}`
    /// was harmless, which it is not.
    func globPatternToRegex() -> String {
        let escaped = replacingOccurrences(
            of: "[.+(){}^$\\\\|]",
            with: "\\\\$0",
            options: .regularExpression
        )
        return "^\(escaped)$"
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
    }

    /// Whether this string matches `searchPattern`, read as a glob.
    ///
    /// **A pattern that will not compile matches nothing, and used to match everything.** The
    /// guard read `else { return true }`, so a malformed glob — an unbalanced `[`, say — turned
    /// a filter the caller wrote to NARROW a set into one that admitted every candidate, with no
    /// diagnostic. Failing open is the wrong direction for a filter: the caller asked for less.
    ///
    /// Reachable only from tests today, which is why this could be corrected without a migration.
    func isMatching(searchPattern: String) -> Bool {
        let pattern = searchPattern.globPatternToRegex()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        return regex.firstMatch(in: self, options: [], range: NSRange(location: 0, length: utf16.count)) != nil
    }
}

internal extension String {
    mutating func addOrSkipMemberAccessLevelAttribute(
        for element: SyntaxStructure,
        basedOn configuration: Configuration
    ) {
        guard configuration.elements.showMemberAccessLevelAttribute == true else { return }
        guard let indicator = element.accessibility.indicator else { return }
        self += indicator
    }
}
