import Foundation
import SwiftUI
import Testing
@testable import SwiftUMLStudio

@Suite("InsightRowView.color")
@MainActor
struct InsightRowViewColorTests {

    @Test("info severity maps to blue")
    func infoIsBlue() {
        #expect(InsightRowView.color(for: .info) == .blue)
    }

    @Test("noteworthy severity maps to orange")
    func noteworthyIsOrange() {
        #expect(InsightRowView.color(for: .noteworthy) == .orange)
    }

    @Test("warning severity maps to red")
    func warningIsRed() {
        #expect(InsightRowView.color(for: .warning) == .red)
    }
}
