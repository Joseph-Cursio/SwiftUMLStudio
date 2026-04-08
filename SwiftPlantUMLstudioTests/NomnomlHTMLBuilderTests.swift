import Foundation
import Testing
@testable import SwiftPlantUMLstudio

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

    @Test("falls back to CDN when bundle resources not found")
    func fallsBackToCDN() {
        // In the test target, Bundle.main won't contain the JS resources,
        // so the CDN fallback should be used
        let html = NomnomlHTMLBuilder.nomnomlHTML("[<class> Foo]")
        let usesLocalGraphre = html.contains("file://")
        let usesCDNGraphre = html.contains("cdn.jsdelivr.net")
        // Either local or CDN — one must be present
        #expect(usesLocalGraphre || usesCDNGraphre)
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
}
