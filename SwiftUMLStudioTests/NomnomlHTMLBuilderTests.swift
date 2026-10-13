import Foundation
import JavaScriptCore
import Testing
@testable import SwiftUMLStudio

@Suite("NomnomlHTMLBuilder")
struct NomnomlHTMLBuilderTests {

    // MARK: - HTML structure

    @Test("output contains canvas element")
    func outputContainsCanvas() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("<canvas"))
        #expect(html.contains("id=\"diagram\""))
    }

    @Test("output contains graphre script reference")
    func outputContainsGraphreScript() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("graphre"))
    }

    @Test("output contains nomnoml script reference")
    func outputContainsNomnomlScript() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("nomnoml"))
    }

    @Test("output contains nomnoml.draw call")
    func outputContainsDrawCall() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("nomnoml.draw(canvas, source)"))
    }

    @Test("output is valid HTML with html and body tags")
    func outputIsValidHTML() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("<html>"))
        #expect(html.contains("</html>"))
        #expect(html.contains("<body"))
        #expect(html.contains("</body>"))
    }

    // MARK: - Source embedding

    @Test("the page hands nomnoml.draw the diagram text unchanged", arguments: [
        "[<struct> Café|~naïve: Int]",
        "[<class> 图表|+emoji: 🎉]",
        "[<class> Foo]",
        "",
        "[Order]->[Customer]\n[Order]+->[LineItem]",
        "[<class> He said \"hi\" \\ to 'me']",
        "line\u{2028}separator\u{2029}paragraph",
        "</script><script>alert('xss')</script>"
    ])
    func pageDrawsOriginalText(_ diagramText: String) throws {
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)
        #expect(try drawnSource(html) == diagramText)
    }

    @Test("literal escapes <, U+2028 and U+2029")
    func literalEscapesScriptHazards() {
        let literal = NomnomlHTMLBuilder.scriptStringLiteral("a<b\u{2028}c\u{2029}")
        #expect(literal == #""a\u003cb\u2028c\u2029""#)
    }

    // MARK: - Script tag sources

    @Test("emits explicit error comments instead of any CDN reference")
    func emitsErrorCommentsNotCDN() {
        // Privacy invariant: the HTML must never reference a third-party CDN.
        // In the test target Bundle.main lacks the bundled JS, so the
        // "missing from app bundle" markers must appear instead. In
        // production both branches resolve to the local file:// path.
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        #expect(html.contains("cdn.jsdelivr.net") == false)
        #expect(html.contains("https://") == false)
        let usesLocalGraphre = html.contains("file://")
        let missingMarker = html.contains("missing from app bundle")
        #expect(usesLocalGraphre || missingMarker)
    }

    // MARK: - Special characters in diagram text

    @Test("diagram text cannot close or derail the page's script element", arguments: [
        "</script><script>alert('xss')</script>",
        "<!--<script>",
        // `<` plus a combining mark is one Character, so a Character-level
        // replace would leave this `<` raw.
        "[A]<\u{0301}/script>"
    ])
    func scriptHazardsAreEscaped(_ diagramText: String) throws {
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)
        let script = try inlineScript(html)
        #expect(script.unicodeScalars.contains("<") == false)
    }

    // MARK: - Dark-mode variants

    @Test("light variant uses a white page background")
    func lightHasWhiteBg() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]", dark: false)
        #expect(html.contains("background:white"))
    }

    @Test("dark variant uses a dark page background")
    func darkHasDarkBg() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]", dark: true)
        #expect(html.contains("background:#1e1e1e"))
        #expect(html.contains("background:white") == false)
    }

    @Test("default variant matches light")
    func defaultMatchesLight() {
        let defaulted = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        let explicit = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]", dark: false)
        #expect(defaulted == explicit)
    }

    // MARK: - Helpers

    /// The body of the page's inline `<script>`, ending where the HTML
    /// parser would end it: at the first `</script>`.
    private func inlineScript(_ html: String) throws -> String {
        let open = try #require(html.range(of: "<script>"))
        let close = try #require(html.range(of: "</script>", range: open.upperBound..<html.endIndex))
        return String(html[open.upperBound..<close.lowerBound])
    }

    /// Runs the page's inline script in JavaScriptCore with `document` and
    /// `nomnoml` stubbed and returns the string it hands to `nomnoml.draw`.
    /// JSContext has no `atob` or `TextDecoder`, so this holds the page to
    /// carrying the source in a form plain JavaScript evaluates.
    private func drawnSource(_ html: String) throws -> String? {
        let context = try #require(JSContext())
        context.evaluateScript("""
            var drawn = null;
            var document = { getElementById: function () { return {}; } };
            var nomnoml = { draw: function (canvas, source) { drawn = source; } };
            """)
        context.evaluateScript(try inlineScript(html))
        if let exception = context.exception {
            Issue.record("Page script threw: \(exception)")
            return nil
        }
        let drawn = try #require(context.objectForKeyedSubscript("drawn"))
        return drawn.isString ? drawn.toString() : nil
    }
}

@Suite("DiagramWebView.svgHTML")
struct DiagramWebViewSVGHTMLTests {

    @Test("light variant uses a white page background")
    func lightBg() {
        let html = DiagramWebView.svgHTML("<svg/>", dark: false)
        #expect(html.contains("background:white"))
    }

    @Test("dark variant uses a dark page background")
    func darkBg() {
        let html = DiagramWebView.svgHTML("<svg/>", dark: true)
        #expect(html.contains("background:#1e1e1e"))
    }

    @Test("inlines the supplied SVG verbatim")
    func inlinesSVG() {
        let svg = "<svg width=\"10\"><rect/></svg>"
        let html = DiagramWebView.svgHTML(svg, dark: false)
        #expect(html.contains(svg))
    }
}
