@testable import SwiftUMLBridgeFramework
import Testing

@Suite("StateMachineExtractor — source shapes")
struct StateMachineExtractorShapeTests {

    @Test("multiple enums+classes in one file each produce a candidate")
    func multipleEnumsOneFile() {
        let source = """
        enum Other { case idle }
        class Bystander {
            var state: Other = .idle
            func nudge() {
                self.state = .idle
            }
        }
        enum Light { case red, green }
        class TrafficLight {
            var state: Light = .red
            func goRed() {
                switch self.state {
                case .green: self.state = .red
                case .red: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        let identifiers = Set(models.map(\.identifier))
        #expect(identifiers.contains("Bystander.Other"))
        #expect(identifiers.contains("TrafficLight.Light"))
    }

    @Test("single-case enum with bare assignment surfaces low-confidence candidate")
    func singleCaseBareAssignment() {
        let source = """
        enum Other { case idle }
        class Bystander {
            var state: Other = .idle
            func nudge() {
                self.state = .idle
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.identifier == "Bystander.Other")
        #expect(models.first?.confidence == .low)
    }

    @Test("switch + assignment inside an extension is detected")
    func extensionHostedStateMachine() {
        let source = """
        enum Light { case red, green }

        class TrafficLight {
            var state: Light = .red
        }

        extension TrafficLight {
            func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        let stateModel = models.first { $0.identifier == "TrafficLight.Light" }
        #expect(stateModel != nil)
        #expect(stateModel?.transitions.count == 2)
        #expect(stateModel?.transitions.allSatisfy { $0.trigger == "toggle" } == true)
    }
}
