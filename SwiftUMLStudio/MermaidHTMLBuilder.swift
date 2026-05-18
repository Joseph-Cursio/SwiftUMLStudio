//
//  MermaidHTMLBuilder.swift
//  SwiftUMLStudio
//
//  Created by joe cursio on 2/27/26.
//

import Foundation

enum MermaidHTMLBuilder {
    nonisolated static func htmlEscape(_ raw: String) -> String {
        raw
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
    }

    nonisolated static func mermaidHTML(_ text: String, dark: Bool = false) -> String {
        let escaped = htmlEscape(text)
        // Render strictly from the bundled mermaid.min.js — no CDN fallback,
        // so the offline / no-third-party-network guarantee holds. The
        // resource is always present in production; the comment fallback only
        // fires in build setups where it isn't (test bundles, previews).
        let scriptTag: String
        if let bundleURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js") {
            scriptTag = "<script src=\"\(bundleURL.absoluteString)\"></script>"
        } else {
            scriptTag = "<!-- mermaid.min.js missing from app bundle -->"
        }
        let theme = dark ? "dark" : "default"
        let background = dark ? "#1e1e1e" : "white"
        return """
        <html>
        <body style="background:\(background); padding:20px;">
        \(scriptTag)
        <script>mermaid.initialize({ startOnLoad: true, theme: '\(theme)' });</script>
        <div class="mermaid">\(escaped)</div>
        </body>
        </html>
        """
    }
}
