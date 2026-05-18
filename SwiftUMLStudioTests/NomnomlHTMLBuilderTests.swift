import Foundation
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

    // MARK: - Base64 encoding

    @Test("output contains base64-encoded diagram text")
    func outputContainsBase64() {
        let diagramText = "[<class> MyClass|+name: String|+greet()]"
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)
        let expectedBase64 = Data(diagramText.utf8).base64EncodedString()
        #expect(html.contains(expectedBase64))
    }

    @Test("base64 decodes back to original diagram text")
    func base64DecodesToOriginal() {
        let diagramText = "[<struct> Point|xPos: Double;yPos: Double]"
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)

        // Extract the base64 string from atob("...")
        let prefix = "atob(\""
        let suffix = "\")"
        guard let startRange = html.range(of: prefix),
              let endRange = html.range(of: suffix, range: startRange.upperBound..<html.endIndex) else {
            Issue.record("Could not find atob() call in HTML output")
            return
        }
        let base64String = String(html[startRange.upperBound..<endRange.lowerBound])
        let decoded = Data(base64Encoded: base64String).flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == diagramText)
    }

    @Test("empty diagram text produces valid base64")
    func emptyDiagramTextProducesValidBase64() {
        let html = NomnomlHTMLBuilder.nomnomlHTML("")
        let expectedBase64 = Data("".utf8).base64EncodedString()
        #expect(html.contains("atob(\"\(expectedBase64)\")"))
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

    @Test("diagram text with HTML special chars is safely encoded via base64")
    func htmlSpecialCharsAreSafe() {
        let diagramText = "<script>alert('xss')</script>"
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)
        // The raw script tag should NOT appear — it's base64-encoded
        #expect(html.contains("<script>alert") == false)
        // But the base64-encoded version should be present
        let expectedBase64 = Data(diagramText.utf8).base64EncodedString()
        #expect(html.contains(expectedBase64))
    }

    @Test("diagram text with quotes is safely encoded via base64")
    func quotesAreSafe() {
        let diagramText = "[<class> He said \"hello\"]"
        let html = NomnomlHTMLBuilder.nomnomlHTML(diagramText)
        let expectedBase64 = Data(diagramText.utf8).base64EncodedString()
        #expect(html.contains(expectedBase64))
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
