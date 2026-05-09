import CoreGraphics
import Foundation
import Testing
@testable import SwiftUMLStudio

@Suite("DiagramViewport")
@MainActor
struct DiagramViewportTests {

    // MARK: - clamp

    @Test("clamp returns minScale when value is below the minimum")
    func clampBelowMin() {
        #expect(DiagramViewport.clamp(0.05) == DiagramViewport.minScale)
    }

    @Test("clamp returns maxScale when value is above the maximum")
    func clampAboveMax() {
        #expect(DiagramViewport.clamp(99.0) == DiagramViewport.maxScale)
    }

    @Test("clamp passes through values inside the range")
    func clampInRange() {
        #expect(DiagramViewport.clamp(1.5) == 1.5)
    }

    // MARK: - fitScale

    @Test("fitScale returns nil when content has zero width or height")
    func fitScaleZeroContent() {
        #expect(DiagramViewport.fitScale(content: .zero, visible: CGSize(width: 100, height: 100)) == nil)
    }

    @Test("fitScale returns nil when visible has zero width or height")
    func fitScaleZeroVisible() {
        #expect(DiagramViewport.fitScale(content: CGSize(width: 100, height: 100), visible: .zero) == nil)
    }

    @Test("fitScale picks the smaller axis ratio with margin applied")
    func fitScalePicksSmallerRatio() throws {
        let content = CGSize(width: 200, height: 100)
        let visible = CGSize(width: 100, height: 100)
        let fit = try #require(DiagramViewport.fitScale(content: content, visible: visible))
        #expect(fit == 0.5 * DiagramViewport.fitMargin)
    }

    @Test("fitScale clamps a content-tiny ratio to maxScale")
    func fitScaleClampsToMax() throws {
        let fit = try #require(
            DiagramViewport.fitScale(
                content: CGSize(width: 1, height: 1),
                visible: CGSize(width: 1000, height: 1000)
            )
        )
        #expect(fit == DiagramViewport.maxScale)
    }

    // MARK: - zoomIn / zoomOut

    @Test("zoomIn multiplies the current scale by zoomStep")
    func zoomIn() {
        let viewport = DiagramViewport()
        viewport.zoomIn()
        #expect(viewport.scale == DiagramViewport.zoomStep)
        #expect(viewport.lastScale == DiagramViewport.zoomStep)
    }

    @Test("zoomOut divides the current scale by zoomStep")
    func zoomOut() {
        let viewport = DiagramViewport()
        viewport.scale = 2.0
        viewport.lastScale = 2.0
        viewport.zoomOut()
        #expect(viewport.scale == 2.0 / DiagramViewport.zoomStep)
    }

    @Test("repeated zoomOut clamps at minScale")
    func zoomOutClamps() {
        let viewport = DiagramViewport()
        for _ in 0..<50 { viewport.zoomOut() }
        #expect(viewport.scale == DiagramViewport.minScale)
    }

    @Test("repeated zoomIn clamps at maxScale")
    func zoomInClamps() {
        let viewport = DiagramViewport()
        for _ in 0..<50 { viewport.zoomIn() }
        #expect(viewport.scale == DiagramViewport.maxScale)
    }

    // MARK: - actualSize / reset / fit

    @Test("actualSize sets scale to 1.0 but leaves offset alone")
    func actualSize() {
        let viewport = DiagramViewport()
        viewport.scale = 0.5
        viewport.offset = CGSize(width: 30, height: 20)
        viewport.lastOffset = CGSize(width: 30, height: 20)
        viewport.actualSize()
        #expect(viewport.scale == 1.0)
        #expect(viewport.offset == CGSize(width: 30, height: 20))
    }

    @Test("reset returns scale to 1.0 and offset to zero")
    func reset() {
        let viewport = DiagramViewport()
        viewport.scale = 2.0
        viewport.lastScale = 2.0
        viewport.offset = CGSize(width: 100, height: 50)
        viewport.lastOffset = CGSize(width: 100, height: 50)
        viewport.reset()
        #expect(viewport.scale == 1.0)
        #expect(viewport.lastScale == 1.0)
        #expect(viewport.offset == .zero)
        #expect(viewport.lastOffset == .zero)
    }

    @Test("fitToWindow uses the smaller axis ratio with margin and resets offset")
    func fitToWindowUsesAxisRatio() {
        let viewport = DiagramViewport()
        viewport.contentSize = CGSize(width: 400, height: 200)
        viewport.visibleSize = CGSize(width: 200, height: 200)
        viewport.offset = CGSize(width: 50, height: 50)
        viewport.lastOffset = CGSize(width: 50, height: 50)
        viewport.fitToWindow()
        #expect(viewport.scale == 0.5 * DiagramViewport.fitMargin)
        #expect(viewport.offset == .zero)
    }

    @Test("fitToWindow is a no-op if content size is unset")
    func fitToWindowNoopOnEmptyContent() {
        let viewport = DiagramViewport()
        viewport.scale = 1.7
        viewport.fitToWindow()
        #expect(viewport.scale == 1.7)
    }

    // MARK: - Gesture deltas

    @Test("updateScale multiplies the last committed scale by the magnification")
    func updateScale() {
        let viewport = DiagramViewport()
        viewport.lastScale = 1.5
        viewport.updateScale(magnification: 2.0)
        #expect(viewport.scale == 3.0)
    }

    @Test("updateScale clamps the resulting scale to the maximum")
    func updateScaleClamps() {
        let viewport = DiagramViewport()
        viewport.lastScale = 4.0
        viewport.updateScale(magnification: 10.0)
        #expect(viewport.scale == DiagramViewport.maxScale)
    }

    @Test("commitScale promotes the live scale into lastScale")
    func commitScale() {
        let viewport = DiagramViewport()
        viewport.scale = 2.5
        viewport.lastScale = 1.0
        viewport.commitScale()
        #expect(viewport.lastScale == 2.5)
    }

    @Test("updateOffset adds the translation to the last committed offset")
    func updateOffset() {
        let viewport = DiagramViewport()
        viewport.lastOffset = CGSize(width: 10, height: 20)
        viewport.updateOffset(translation: CGSize(width: 5, height: -3))
        #expect(viewport.offset == CGSize(width: 15, height: 17))
    }

    @Test("commitOffset promotes the live offset into lastOffset")
    func commitOffset() {
        let viewport = DiagramViewport()
        viewport.offset = CGSize(width: 12, height: 8)
        viewport.lastOffset = .zero
        viewport.commitOffset()
        #expect(viewport.lastOffset == CGSize(width: 12, height: 8))
    }

    // MARK: - Label

    @Test("zoomPercentLabel rounds to the nearest percent")
    func zoomPercentLabelRounds() {
        let viewport = DiagramViewport()
        viewport.scale = 1.234
        #expect(viewport.zoomPercentLabel == "123%")
    }

    @Test("zoomPercentLabel reports 100% at default scale")
    func zoomPercentLabelDefault() {
        let viewport = DiagramViewport()
        #expect(viewport.zoomPercentLabel == "100%")
    }
}
