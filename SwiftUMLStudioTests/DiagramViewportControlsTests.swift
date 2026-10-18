import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

@Suite("DiagramViewportControls")
@MainActor
struct DiagramViewportControlsTests {

    /// The buttons show only an icon, so the label's title is all VoiceOver has to read.
    @Test(
        "each icon-only button names itself",
        arguments: [
            ("viewportZoomOut", "Zoom Out"),
            ("viewportZoomIn", "Zoom In"),
            ("viewportFit", "Fit to Window"),
            ("viewportActualSize", "Actual Size"),
            ("viewportReset", "Reset Zoom and Pan")
        ]
    )
    func buttonNames(identifier: String, title: String) throws {
        let view = try DiagramViewportControls(viewport: DiagramViewport()).inspect()
        let label = try view.find(viewWithAccessibilityIdentifier: identifier).button().labelView().label()
        #expect(try label.title().text().string() == title)
    }
}
