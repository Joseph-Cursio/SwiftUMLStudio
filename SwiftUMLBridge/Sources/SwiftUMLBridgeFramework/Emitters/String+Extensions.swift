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
    func isMatching(searchPattern: String) -> Bool {
        let pattern = "^\(searchPattern)$"
            .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "[^/]")
            .replacingOccurrences(of: "**/", with: "(.+/)?")
            .replacingOccurrences(of: "**", with: ".+")
            .replacingOccurrences(of: "*", with: "([^/]+)?")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return true }
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
