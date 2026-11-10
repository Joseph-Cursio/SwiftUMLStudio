@testable import SwiftUMLBridgeFramework
import Testing

@Suite("StateMachineExtractor")
struct StateMachineExtractorTests {

    // MARK: - Positive cases

    @Test("detects simple traffic-light state machine")
    func simpleTrafficLight() {
        let source = """
        enum Light { case red, yellow, green }

        class TrafficLight {
            var state: Light = .red

            func advance() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .yellow
                case .yellow: self.state = .red
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        let model = models.first
        #expect(model?.hostType == "TrafficLight")
        #expect(model?.enumType == "Light")
        #expect(model?.states.map(\.name) == ["red", "yellow", "green"])
        #expect(model?.transitions.count == 3)
        #expect(model?.transitions.allSatisfy { $0.trigger == "advance" } == true)
    }

    @Test("first enum case is marked initial")
    func firstCaseIsInitial() {
        let source = """
        enum Flow { case idle, running, done }
        class Runner {
            var state: Flow = .idle
            func start() {
                switch self.state {
                case .idle: self.state = .running
                case .running: self.state = .done
                case .done: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        let idle = models.first?.states.first { $0.name == "idle" }
        #expect(idle?.isInitial == true)
    }

    @Test("terminal-looking sink state is marked final")
    func sinkStateIsFinal() {
        let source = """
        enum Flow { case idle, running, done }
        class Runner {
            var state: Flow = .idle
            func run() {
                switch self.state {
                case .idle: self.state = .running
                case .running: self.state = .done
                case .done: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        let done = models.first?.states.first { $0.name == "done" }
        #expect(done?.isFinal == true)
    }

    @Test("bare property reference without self. is accepted")
    func barePropertyAssignment() {
        let source = """
        enum State { case one, two }
        struct Host {
            var state: State = .one
            mutating func toggle() {
                switch state {
                case .one: state = .two
                case .two: state = .one
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.transitions.count == 2)
    }
}
