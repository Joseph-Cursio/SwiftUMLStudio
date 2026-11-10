import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("StateMachineConfidenceBanner")
@MainActor
struct StateMachineConfidenceBannerTests {

    private func makeModel(confidence: DetectionConfidence) -> StateMachineModel {
        StateMachineModel(
            hostType: "Host", enumType: "Enum",
            states: [StateMachineState(name: "idle", isInitial: true)],
            transitions: [],
            confidence: confidence,
            notes: confidence == .high ? [] : ["example note"]
        )
    }

    @Test("medium confidence uses info symbol and orange tint")
    func mediumConfidenceStyling() {
        let banner = StateMachineConfidenceBanner(model: makeModel(confidence: .medium))
        #expect(banner.symbol == "info.circle.fill")
        #expect(banner.tint == .orange)
        #expect(banner.headline == "Partially inferred state machine")
    }

    @Test("low confidence uses warning symbol and red tint")
    func lowConfidenceStyling() {
        let banner = StateMachineConfidenceBanner(model: makeModel(confidence: .low))
        #expect(banner.symbol == "exclamationmark.triangle.fill")
        #expect(banner.tint == .red)
        #expect(banner.headline == "Low-confidence state machine")
    }

    @Test("high confidence headline is empty (view suppresses banner)")
    func highConfidenceHeadlineEmpty() {
        let banner = StateMachineConfidenceBanner(model: makeModel(confidence: .high))
        #expect(banner.headline.isEmpty)
    }
}
