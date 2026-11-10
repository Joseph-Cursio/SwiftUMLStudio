import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.moduleColor")
struct NativeDiagramGeometryModuleColorTests {

    @Test("returns the same color for the same module name")
    func deterministic() {
        let first = NativeDiagramGeometry.moduleColor(for: "Networking")
        let second = NativeDiagramGeometry.moduleColor(for: "Networking")
        #expect(first == second)
    }

    @Test("different modules generally get different colors")
    func variesAcrossModules() {
        let networking = NativeDiagramGeometry.moduleColor(for: "Networking")
        let uiColor = NativeDiagramGeometry.moduleColor(for: "UI")
        #expect(networking != uiColor)
    }
}
