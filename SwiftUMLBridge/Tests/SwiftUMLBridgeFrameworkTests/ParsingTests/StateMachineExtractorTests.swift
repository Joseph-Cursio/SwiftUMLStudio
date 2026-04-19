import Testing
@testable import SwiftUMLBridgeFramework

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
        let idle = models.first?.states.first(where: { $0.name == "idle" })
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
        let done = models.first?.states.first(where: { $0.name == "done" })
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

    // MARK: - Negative cases

    @Test("enum with associated values is rejected")
    func enumWithAssociatedValuesRejected() {
        let source = """
        enum Result { case success(Int), failure(Error) }
        class Host {
            var state: Result = .success(0)
            func update() {
                switch self.state {
                case .success: self.state = .failure(NSError())
                case .failure: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.isEmpty)
    }

    @Test("property without switch-driven transitions yields no candidate")
    func noSwitchNoCandidate() {
        let source = """
        enum Light { case red, green }
        class Host {
            var state: Light = .red
            func reset() { self.state = .red }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.isEmpty)
    }

    @Test("switch on a different property does not produce transitions")
    func switchOnDifferentPropertyIgnored() {
        let source = """
        enum Light { case red, green }
        enum Other { case a, b }
        class Host {
            var state: Light = .red
            var other: Other = .a
            func change() {
                switch self.other {
                case .a: self.state = .green
                case .b: self.state = .red
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.isEmpty)
    }

    @Test("two hosts sharing the same enum are each emitted")
    func multipleHostsSameEnum() {
        let source = """
        enum Light { case red, green }
        class Foo {
            var state: Light = .red
            func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        class Bar {
            var state: Light = .red
            func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 2)
        #expect(Set(models.map(\.hostType)) == ["Foo", "Bar"])
    }
}
