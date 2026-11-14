import Foundation
import SwiftUMLBridgeFramework

/// Presents through `inner`, then says on stderr when the SVG layout put the boxes on its grid
/// instead of laying them out (#150). The diagram is still written and the exit status is the
/// same: only the boxes are not where the layout would put them, and nothing else said so.
struct LayoutFallbackReporter: DiagramPresenting {
    let inner: any DiagramPresenting
    /// Where the warning goes: stderr, or a test's buffer.
    var report: @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }

    func present(script: any DiagramOutputting) async {
        await inner.present(script: script)
        if let warning = Self.warning(for: script) {
            report(warning)
        }
    }

    /// The line to print for `script`, or `nil` when its layout did not fall back.
    static func warning(for script: any DiagramOutputting) -> String? {
        guard let reason = script.layoutGraph?.fallbackReason else { return nil }
        return "warning: the SVG layout failed (\(reason)), so the boxes are on a grid\n"
    }
}
