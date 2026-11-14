import SwiftUI
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry.arrowStrokeStyle")
struct ArrowStrokeStyleTests {

    @Test("async messages are dashed")
    func asyncDashed() {
        let style = NativeSequenceGeometry.arrowStrokeStyle(isAsync: true)
        #expect(style.dash == [4, 3])
    }

    @Test("sync messages are solid")
    func syncSolid() {
        let style = NativeSequenceGeometry.arrowStrokeStyle(isAsync: false)
        #expect(style.dash.isEmpty)
    }
}
