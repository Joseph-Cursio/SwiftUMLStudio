import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Studio's native canvas draws the same label through this function, so the two cannot diverge.
@Suite("ComponentSVGRenderer stereotype labels")
struct ComponentSVGRendererStereotypeTests {

    @Test(
        "each kind maps to its UML stereotype",
        arguments: [
            (ComponentKind.executable, "executable"),
            (.library, "library"),
            (.test, "test"),
        ]
    )
    func labelsPerKind(kind: ComponentKind, label: String) {
        #expect(ComponentSVGRenderer.stereotypeLabel(for: kind) == label)
    }

    /// `.other` is the catch-all, and «other» would read as a real UML stereotype.
    @Test("the catch-all kind renders as «component», not «other»")
    func otherRendersAsComponent() {
        #expect(ComponentSVGRenderer.stereotypeLabel(for: .other) == "component")
    }
}
