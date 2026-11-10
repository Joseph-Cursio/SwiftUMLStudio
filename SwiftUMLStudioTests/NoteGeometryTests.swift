import CoreGraphics
import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NativeSequenceGeometry note sizing")
struct NoteGeometryTests {

    @Test("short notes use the minimum width")
    func minimumWidth() {
        #expect(NativeSequenceGeometry.noteWidth(for: "hi") == 100)
    }

    @Test("long notes scale with character count")
    func scalesWithCharacters() {
        let text = String(repeating: "x", count: 30)
        #expect(NativeSequenceGeometry.noteWidth(for: text) == 210)
    }

    @Test("note rect is centered on the given point")
    func noteCentered() {
        let rect = NativeSequenceGeometry.noteRect(text: "hi", centerX: 100, posY: 50)
        #expect(rect.midX == 100)
        #expect(rect.midY == 50)
    }
}
