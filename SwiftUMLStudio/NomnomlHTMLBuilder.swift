import Foundation

enum NomnomlHTMLBuilder {
    nonisolated static func nomnomlHTML(_ text: String) -> String {
        // Base64-encode the nomnoml source to avoid any escaping issues
        let base64 = Data(text.utf8).base64EncodedString()

        let graphreTag: String
        if let bundleURL = Bundle.main.url(forResource: "graphre", withExtension: "js") {
            graphreTag = "<script src=\"\(bundleURL.absoluteString)\"></script>"
        } else {
            graphreTag = "<script src=\"https://cdn.jsdelivr.net/npm/graphre/dist/graphre.js\"></script>"
        }

        let nomnomlTag: String
        if let bundleURL = Bundle.main.url(forResource: "nomnoml", withExtension: "js") {
            nomnomlTag = "<script src=\"\(bundleURL.absoluteString)\"></script>"
        } else {
            nomnomlTag = "<script src=\"https://cdn.jsdelivr.net/npm/nomnoml/dist/nomnoml.js\"></script>"
        }

        return """
        <html>
        <body style="background:white; padding:20px; margin:0;">
        <canvas id="diagram"></canvas>
        \(graphreTag)
        \(nomnomlTag)
        <script>
            var source = atob("\(base64)");
            var canvas = document.getElementById('diagram');
            nomnoml.draw(canvas, source);
        </script>
        </body>
        </html>
        """
    }
}
