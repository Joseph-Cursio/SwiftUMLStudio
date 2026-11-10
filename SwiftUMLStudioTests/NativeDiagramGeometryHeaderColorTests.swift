import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.headerColor")
struct NativeDiagramGeometryHeaderColorTests {

    @Test("every known stereotype resolves to a distinct color")
    func knownStereotypes() {
        let keys = ["class", "struct", "enum", "protocol", "actor", "extension", "macro", "warning"]
        for key in keys {
            _ = NativeDiagramGeometry.headerColor(for: key)
        }
        #expect(NativeDiagramGeometry.headerColors.count == keys.count)
    }

    @Test("unknown stereotype falls back to the class color")
    func unknownFallback() {
        let fallback = NativeDiagramGeometry.headerColor(for: "unknown-kind")
        #expect(fallback == NativeDiagramGeometry.headerColors["class"])
    }

    @Test("nil stereotype falls back to the class color")
    func nilStereotype() {
        #expect(
            NativeDiagramGeometry.headerColor(for: nil) == NativeDiagramGeometry.headerColors["class"]
        )
    }
}
