import AppKit
import SwiftUI

/// Wraps a SwiftUI view in an `NSHostingView` subclass that intercepts
/// ⌘+scroll-wheel events. Used by the native diagram canvases to support
/// Cmd+scroll zoom alongside the existing pinch and keyboard shortcuts.
/// Non-⌘ scroll events fall through to the SwiftUI content unchanged so
/// trackpad pan / overflow scrolling continues to work.
struct CommandScrollWrapper<Content: View>: NSViewRepresentable {
    let content: Content
    let onCommandScroll: (CGFloat) -> Void

    init(
        @ViewBuilder content: () -> Content,
        onCommandScroll: @escaping (CGFloat) -> Void
    ) {
        self.content = content()
        self.onCommandScroll = onCommandScroll
    }

    func makeNSView(context: Context) -> CommandScrollHostingView<Content> {
        let view = CommandScrollHostingView(rootView: content)
        view.onCommandScroll = onCommandScroll
        return view
    }

    func updateNSView(_ nsView: CommandScrollHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.onCommandScroll = onCommandScroll
    }
}

/// `NSHostingView` subclass that intercepts ⌘+scroll-wheel events and forwards
/// the vertical delta to a callback. All other scroll events pass through to
/// `super` so the SwiftUI content's gesture handlers see them normally.
final class CommandScrollHostingView<Content: View>: NSHostingView<Content> {
    var onCommandScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            onCommandScroll?(event.scrollingDeltaY)
            return
        }
        super.scrollWheel(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
