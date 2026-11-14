//  Tests for DiagramMode, FileNode, and MermaidHTMLBuilder.

import Foundation
@testable import SwiftUMLStudio
import Testing

// MARK: - MermaidHTMLBuilder Tests

@Suite("MermaidHTMLBuilder") @MainActor
struct MermaidHTMLBuilderTests {

    // MARK: htmlEscape

    @Test("htmlEscape leaves plain text unchanged")
    func htmlEscapePlainText() {
        #expect(MermaidHTMLBuilder.htmlEscape("hello world") == "hello world")
    }

    @Test("htmlEscape replaces & with &amp;")
    func htmlEscapeAmpersand() {
        #expect(MermaidHTMLBuilder.htmlEscape("A & B") == "A &amp; B")
    }

    @Test("htmlEscape replaces < with &lt;")
    func htmlEscapeLessThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a < b") == "a &lt; b")
    }

    @Test("htmlEscape replaces > with &gt;")
    func htmlEscapeGreaterThan() {
        #expect(MermaidHTMLBuilder.htmlEscape("a > b") == "a &gt; b")
    }

    @Test("htmlEscape replaces all three characters in one string")
    func htmlEscapeAllSpecialChars() {
        #expect(MermaidHTMLBuilder.htmlEscape("<a & b>") == "&lt;a &amp; b&gt;")
    }

    @Test("htmlEscape escapes & before < and > to avoid double-escaping")
    func htmlEscapeOrderPreventDoubleEscape() {
        // If < were escaped first to &lt;, the & in &lt; could be re-escaped to &amp;lt;
        #expect(MermaidHTMLBuilder.htmlEscape("<") == "&lt;")
        #expect(MermaidHTMLBuilder.htmlEscape(">") == "&gt;")
    }

    @Test("htmlEscape handles empty string")
    func htmlEscapeEmpty() {
        #expect(MermaidHTMLBuilder.htmlEscape("").isEmpty)
    }

    @Test("htmlEscape handles multiple consecutive special chars")
    func htmlEscapeConsecutive() {
        #expect(MermaidHTMLBuilder.htmlEscape("<<>>&&") == "&lt;&lt;&gt;&gt;&amp;&amp;")
    }

    // MARK: mermaidHTML

    @Test("mermaidHTML contains the escaped diagram text")
    func mermaidHTMLContainsDiagramText() {
        let html = MermaidHTMLBuilder.mermaidHTML("A -> B")
        #expect(html.contains("A -&gt; B"))
    }

    @Test("mermaidHTML contains mermaid div")
    func mermaidHTMLContainsMermaidDiv() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("<div class=\"mermaid\">"))
    }

    @Test("mermaidHTML emits a local script tag or a missing-bundle marker (never a CDN URL)")
    func mermaidHTMLNeverReferencesCDN() {
        // Privacy invariant: HTML must not contain any third-party CDN URL.
        // In the test target Bundle.main lacks mermaid.min.js, so the
        // "missing from app bundle" marker appears; in production the local
        // file:// script tag does.
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("cdn.jsdelivr.net") == false)
        #expect(html.contains("https://") == false)
        let usesLocalScript = html.contains("file://")
        let missingMarker = html.contains("missing from app bundle")
        #expect(usesLocalScript || missingMarker)
    }

    @Test("mermaidHTML escapes XSS injection attempt")
    func mermaidHTMLEscapesInjection() {
        let html = MermaidHTMLBuilder.mermaidHTML("</div><script>evil()</script>")
        #expect(html.contains("<script>evil()") == false)
        #expect(html.contains("&lt;/div&gt;&lt;script&gt;evil()&lt;/script&gt;"))
    }

    // MARK: - Dark-mode variants

    @Test("mermaidHTML(dark: false) emits the default theme and white bg")
    func mermaidHTMLLightDefaults() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD", dark: false)
        #expect(html.contains("theme: 'default'"))
        #expect(html.contains("background:white"))
    }

    @Test("mermaidHTML(dark: true) emits the dark theme and dark bg")
    func mermaidHTMLDarkVariant() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD", dark: true)
        #expect(html.contains("theme: 'dark'"))
        #expect(html.contains("background:#1e1e1e"))
        #expect(html.contains("theme: 'default'") == false)
    }

    @Test("mermaidHTML defaults to the light variant when dark is omitted")
    func mermaidHTMLDefaultIsLight() {
        let html = MermaidHTMLBuilder.mermaidHTML("graph TD")
        #expect(html.contains("theme: 'default'"))
    }
}
