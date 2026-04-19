import Foundation
import SwiftUI
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("StateMachineConfidenceBanner")
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

@Suite("DiagramPreviewView.lowConfidenceModel")
struct DiagramPreviewViewLowConfidenceTests {

    private func makeModel(confidence: DetectionConfidence) -> StateMachineModel {
        StateMachineModel(
            hostType: "H", enumType: "E",
            states: [], transitions: [],
            confidence: confidence, notes: []
        )
    }

    @Test("non-state-machine mode never surfaces banner")
    func wrongModeReturnsNil() {
        let model = makeModel(confidence: .low)
        #expect(
            DiagramPreviewView.lowConfidenceModel(
                diagramMode: .classDiagram, stateMachineModel: model
            ) == nil
        )
    }

    @Test("nil state machine model returns nil")
    func nilModelReturnsNil() {
        #expect(
            DiagramPreviewView.lowConfidenceModel(
                diagramMode: .stateMachine, stateMachineModel: nil
            ) == nil
        )
    }

    @Test("high-confidence model returns nil")
    func highConfidenceReturnsNil() {
        let model = makeModel(confidence: .high)
        #expect(
            DiagramPreviewView.lowConfidenceModel(
                diagramMode: .stateMachine, stateMachineModel: model
            ) == nil
        )
    }

    @Test("medium-confidence model surfaces the banner model")
    func mediumConfidenceSurfaces() {
        let model = makeModel(confidence: .medium)
        let banner = DiagramPreviewView.lowConfidenceModel(
            diagramMode: .stateMachine, stateMachineModel: model
        )
        #expect(banner?.confidence == .medium)
    }

    @Test("low-confidence model surfaces the banner model")
    func lowConfidenceSurfaces() {
        let model = makeModel(confidence: .low)
        let banner = DiagramPreviewView.lowConfidenceModel(
            diagramMode: .stateMachine, stateMachineModel: model
        )
        #expect(banner?.confidence == .low)
    }
}
