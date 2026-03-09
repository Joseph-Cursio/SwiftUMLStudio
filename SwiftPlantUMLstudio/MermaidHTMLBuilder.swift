//
//  MermaidHTMLBuilder.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 2/27/26.
//

enum MermaidHTMLBuilder {
    nonisolated static func htmlEscape(_ raw: String) -> String {
        raw
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
    }

    nonisolated static func mermaidHTML(_ text: String) -> String {
        let escaped = htmlEscape(text)
        return """
        <html>
        <body style="background:white; padding:20px;">
        <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
        <script>mermaid.initialize({ startOnLoad: true, theme: 'default' });</script>
        <div class="mermaid">\(escaped)</div>
        </body>
        </html>
        """
    }
}
