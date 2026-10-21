import Foundation

/// The `<script>` elements the web-view diagram pages load their renderers through.
enum BundledScript {
    /// A `<script>` element for `<resource>.js` in the app bundle.
    ///
    /// Pages render strictly from bundled scripts — no CDN fallback, so the
    /// offline / no-third-party-network guarantee holds. The resources are
    /// always present in production; the comment returned when one is missing
    /// only appears in build setups without them (test bundles, previews).
    nonisolated static func tag(resource: String) -> String {
        if let bundleURL = Bundle.main.url(forResource: resource, withExtension: "js") {
            return "<script src=\"\(bundleURL.absoluteString)\"></script>"
        }
        return "<!-- \(resource).js missing from app bundle -->"
    }
}
