//
//  DiagramWebView.swift
//  SwiftUMLStudio
//
//  Created by joe cursio on 2/27/26.
//

import SwiftUI
import WebKit
import SwiftUMLBridgeFramework

/// Renders a diagram using the native SwiftUI WebView (macOS 26+).
/// - PlantUML diagrams go to ``PlantTextPreview``, which loads planttext.com only after
///   ``PlantUMLConsent`` is granted and otherwise asks in place of the preview.
/// - Mermaid diagrams load an HTML string into a `WebPage` instance.
struct DiagramWebView: View {
    var script: (any DiagramOutputting)?
    /// The Format picker's value, so the PlantUML preview can explain a fallback.
    var requestedFormat: DiagramFormat?
    var consent: PlantUMLConsent = .shared
    /// Offered on the PlantUML consent card; `nil` hides that choice.
    var onUseMermaid: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var localPage = WebPage()

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            switch script?.format {
            case .plantuml:
                if let script {
                    PlantTextPreview(
                        script: script,
                        requestedFormat: requestedFormat,
                        consent: consent,
                        onUseMermaid: onUseMermaid
                    )
                }
            case .mermaid:
                localWebView(html: MermaidHTMLBuilder.mermaidHTML(script?.text ?? "", dark: dark))
            case .nomnoml:
                localWebView(html: NomnomlHTMLBuilder.nomnomlHTML(script?.text ?? "", dark: dark))
            case .svg:
                localWebView(html: svgHTML(script?.text ?? "", dark: dark))
            case nil:
                EmptyView()
            }
        }
    }

    /// Wraps raw SVG in a minimal HTML page with pan/zoom support.
    nonisolated static func svgHTML(_ svg: String, dark: Bool) -> String {
        let background = dark ? "#1e1e1e" : "white"
        return """
        <html>
        <body style="background:\(background); margin:0; padding:20px; overflow:auto;">
        \(svg)
        </body>
        </html>
        """
    }

    private func svgHTML(_ svg: String, dark: Bool) -> String {
        Self.svgHTML(svg, dark: dark)
    }

    private func localWebView(html: String) -> some View {
        WebView(localPage)
            .task(id: script?.text) {
                guard let text = script?.text, !text.isEmpty else { return }
                let baseURL = Bundle.main.resourceURL ?? URL(string: "about:blank")!
                _ = localPage.load(html: html, baseURL: baseURL)
            }
    }
}
