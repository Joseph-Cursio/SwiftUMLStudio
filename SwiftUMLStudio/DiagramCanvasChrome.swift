import SwiftUI

/// The trailing canvas chrome shared by every renderer: button accessibility
/// metadata and the `onAppear`/`onChange` wiring that keeps the viewport's
/// content and visible sizes in sync with the geometry.
struct DiagramCanvasChrome: ViewModifier {
    let viewport: DiagramViewport
    let contentSize: CGSize
    let visibleSize: CGSize
    let label: String
    let identifier: String

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint("Double-tap to reset zoom and position")
            .accessibilityIdentifier(identifier)
            .onAppear {
                viewport.contentSize = contentSize
                viewport.visibleSize = visibleSize
            }
            .onChange(of: visibleSize) { _, newSize in
                viewport.visibleSize = newSize
            }
    }
}
