import Foundation
import JavaScriptCore
@testable import SwiftUMLStudio
import Testing

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
