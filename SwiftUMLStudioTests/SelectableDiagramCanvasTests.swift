import SwiftUI
import Testing
@testable import SwiftUMLStudio

/// The selection handlers themselves are tested through each canvas, in NativeDiagramViewTests
/// and NativeSequenceDiagramViewTests. This pins the key each arrow direction listens for, which
/// `selectableCanvasInteraction` maps a key press back through (#209).
@Suite("SelectableDiagramCanvas arrow keys")
struct SelectableDiagramCanvasTests {

    @Test("each direction listens for its own arrow key", arguments: [
        (NativeDiagramGeometry.NavigationDirection.upward, KeyEquivalent.upArrow),
        (.down, .downArrow),
        (.left, .leftArrow),
        (.right, .rightArrow)
    ])
    func arrowKey(direction: NativeDiagramGeometry.NavigationDirection, key: KeyEquivalent) {
        #expect(direction.key == key)
    }
}
