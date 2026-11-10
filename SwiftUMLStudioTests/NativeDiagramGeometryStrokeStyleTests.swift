import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeDiagramGeometry.strokeStyle")
struct NativeDiagramGeometryStrokeStyleTests {

    @Test("realization is dashed")
    func realizationDashed() {
        let style = NativeDiagramGeometry.strokeStyle(for: .realization)
        #expect(style.dash == [6, 3])
    }

    @Test("dependency is dashed")
    func dependencyDashed() {
        let style = NativeDiagramGeometry.strokeStyle(for: .dependency)
        #expect(style.dash == [6, 3])
    }

    @Test("inheritance is solid")
    func inheritanceSolid() {
        let style = NativeDiagramGeometry.strokeStyle(for: .inheritance)
        #expect(style.dash.isEmpty)
    }

    @Test("composition and association are solid")
    func othersSolid() {
        #expect(NativeDiagramGeometry.strokeStyle(for: .composition).dash.isEmpty)
        #expect(NativeDiagramGeometry.strokeStyle(for: .association).dash.isEmpty)
    }
}
