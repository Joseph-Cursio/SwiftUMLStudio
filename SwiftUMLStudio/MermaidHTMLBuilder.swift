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
        let scriptTag = BundledScript.tag(resource: "mermaid.min")
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
