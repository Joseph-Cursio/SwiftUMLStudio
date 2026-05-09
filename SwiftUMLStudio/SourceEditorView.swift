import AppKit
import SwiftUI

/// Read-only Swift source viewer with optional line highlighting.
/// Used by the developer-layout middle pane and by Phase 4's
/// "Reveal in Source" diagram navigation.
struct SourceEditorView: View {
    let content: String
    let hasSelection: Bool
    var highlightedLine: Int?

    var body: some View {
        if hasSelection {
            SourceTextView(content: content, highlightedLine: highlightedLine)
        } else {
            ContentUnavailableView(
                "Select a file",
                systemImage: "doc.text",
                description: Text("Choose a Swift file from the browser to view its source.")
            )
        }
    }

    /// Compute the NSRange of `line` (1-based) inside `source`, excluding the
    /// trailing newline. Returns `nil` if `line` is out of range.
    /// Exposed for unit testing.
    static func lineRange(line: Int, in source: String) -> NSRange? {
        guard line >= 1 else { return nil }
        let lines = source.components(separatedBy: "\n")
        guard line <= lines.count else { return nil }

        var location = 0
        for index in 0..<(line - 1) {
            let lineLength = (lines[index] as NSString).length
            location += lineLength + 1
        }
        let targetLength = (lines[line - 1] as NSString).length
        return NSRange(location: location, length: targetLength)
    }
}

/// NSViewRepresentable wrapper around an NSTextView that scrolls to and
/// highlights `highlightedLine` whenever it is non-nil.
private struct SourceTextView: NSViewRepresentable {
    let content: String
    let highlightedLine: Int?

    private static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.3)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.allowsUndo = false
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.setAccessibilityLabel("Swift source viewer")
            textView.setAccessibilityIdentifier("sourceTextView")
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != content {
            textView.string = content
        }
        applyHighlight(in: textView)
    }

    private func applyHighlight(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let everything = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.backgroundColor, range: everything)

        guard let line = highlightedLine,
              let range = SourceEditorView.lineRange(line: line, in: textView.string)
        else { return }

        storage.addAttribute(.backgroundColor, value: Self.highlightColor, range: range)
        textView.scrollRangeToVisible(range)
    }
}
