import SwiftUI
import SwiftUMLBridgeFramework

/// Shown above the native canvas when the SVG layout failed and put the boxes on a grid (#150).
/// The grid keeps every type and relationship, so without this nothing said the diagram was not
/// laid out.
struct LayoutFallbackBanner: View {
    /// Why the layout fell back, from `LayoutGraph.fallbackReason`.
    let reason: String

    var body: some View {
        NoticeBanner(systemImage: "square.grid.3x3", identifier: "layoutFallbackBanner") {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headline).font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    static let headline = "Boxes placed on a grid"

    var detail: String {
        "The automatic layout failed (\(reason)), so every type and relationship is drawn, "
            + "but not where the layout would put them."
    }

    /// The reason to show for `script`, or `nil` when the banner should stay hidden: while a
    /// diagram is generating, for every format but SVG (the only one this layout draws), and
    /// when the layout did not fall back.
    static func reason(for script: (any DiagramOutputting)?, isGenerating: Bool) -> String? {
        guard !isGenerating, let script, script.format == .svg else { return nil }
        return script.layoutGraph?.fallbackReason
    }
}
