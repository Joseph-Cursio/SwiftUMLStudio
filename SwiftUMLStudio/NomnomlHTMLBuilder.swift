import Foundation

enum NomnomlHTMLBuilder {
    nonisolated static func nomnomlHTML(_ text: String, dark: Bool = false) -> String {
        let source = scriptStringLiteral(text)
        let graphreTag = BundledScript.tag(resource: "graphre")
        let nomnomlTag = BundledScript.tag(resource: "nomnoml")

        // Nomnoml's canvas drawing uses fixed light colors. We can only adapt
        // the surrounding page background; the diagram itself stays light.
        let background = dark ? "#1e1e1e" : "white"
        return """
        <html>
        <body style="background:\(background); padding:20px; margin:0;">
        <canvas id="diagram"></canvas>
        \(graphreTag)
        \(nomnomlTag)
        <script>
            var source = \(source);
            var canvas = document.getElementById('diagram');
            nomnoml.draw(canvas, source);
        </script>
        </body>
        </html>
        """
    }

    /// `text` as a JavaScript string literal that can sit inside an inline
    /// `<script>` element.
    ///
    /// The page used to carry the source as base64 and decode it with
    /// `atob`, which returns one Latin-1 character per UTF-8 byte, so every
    /// non-ASCII character reached nomnoml as mojibake. A literal needs no
    /// decoding. A JSON string is a valid one, but JSON leaves `<` raw, which
    /// lets `</script>` in the source end the element and `<!--` change how
    /// the HTML parser finds its end, and it leaves U+2028 and U+2029 raw,
    /// which engines before ES2019 read as line terminators. All three are
    /// escaped here. The loop works on scalars because a `<` followed by a
    /// combining mark is one `Character` and a `Character` match would miss it.
    nonisolated static func scriptStringLiteral(_ text: String) -> String {
        // Encoding a `String` never throws — only non-finite floats do.
        guard let data = try? JSONEncoder().encode(text),
              let json = String(bytes: data, encoding: .utf8) else { return "\"\"" }
        var literal = ""
        for scalar in json.unicodeScalars {
            switch scalar {
            case "<": literal += "\\u003c"
            case "\u{2028}": literal += "\\u2028"
            case "\u{2029}": literal += "\\u2029"
            default: literal.unicodeScalars.append(scalar)
            }
        }
        return literal
    }
}
