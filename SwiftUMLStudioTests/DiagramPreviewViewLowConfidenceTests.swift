import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("DiagramPreviewView.lowConfidenceModel")
@MainActor
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
