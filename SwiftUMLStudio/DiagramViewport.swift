import Observation
import SwiftUI

/// Shared zoom/pan state for the native diagram canvases.
/// One instance per `DiagramPreviewView`; consumed by `NativeDiagramView`,
/// `NativeSequenceDiagramView`, and `NativeActivityDiagramView`.
@Observable
@MainActor
final class DiagramViewport {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    var lastScale: CGFloat = 1.0
    var lastOffset: CGSize = .zero

    var selectedNodeId: String?

    var contentSize: CGSize = .zero
    var visibleSize: CGSize = .zero

    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 5.0
    static let zoomStep: CGFloat = 1.25
    static let fitMargin: CGFloat = 0.95

    func zoomIn() {
        applyScale(scale * Self.zoomStep, animated: true)
    }

    func zoomOut() {
        applyScale(scale / Self.zoomStep, animated: true)
    }

    func actualSize() {
        applyScale(1.0, animated: true)
    }

    func reset() {
        withAnimation(.easeInOut(duration: 0.25)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    func fitToWindow() {
        guard let fit = Self.fitScale(content: contentSize, visible: visibleSize) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            scale = fit
            lastScale = fit
            offset = .zero
            lastOffset = .zero
        }
    }

    func updateScale(magnification: CGFloat) {
        applyScale(lastScale * magnification, animated: false)
    }

    func commitScale() {
        lastScale = scale
    }

    func updateOffset(translation: CGSize) {
        offset = CGSize(
            width: lastOffset.width + translation.width,
            height: lastOffset.height + translation.height
        )
    }

    func commitOffset() {
        lastOffset = offset
    }

    var zoomPercentLabel: String {
        "\(Int((scale * 100).rounded()))%"
    }

    private func applyScale(_ newScale: CGFloat, animated: Bool) {
        let clamped = Self.clamp(newScale)
        if animated {
            withAnimation(.easeInOut(duration: 0.15)) {
                scale = clamped
                lastScale = clamped
            }
        } else {
            scale = clamped
        }
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        max(minScale, min(maxScale, value))
    }

    /// Returns the scale that fits `content` within `visible` (with `fitMargin`
    /// breathing room), clamped to `[minScale, maxScale]`. Returns `nil` if either
    /// size has a non-positive dimension.
    static func fitScale(content: CGSize, visible: CGSize) -> CGFloat? {
        guard content.width > 0, content.height > 0,
              visible.width > 0, visible.height > 0 else { return nil }
        let scaleX = visible.width / content.width
        let scaleY = visible.height / content.height
        return clamp(min(scaleX, scaleY) * fitMargin)
    }
}
