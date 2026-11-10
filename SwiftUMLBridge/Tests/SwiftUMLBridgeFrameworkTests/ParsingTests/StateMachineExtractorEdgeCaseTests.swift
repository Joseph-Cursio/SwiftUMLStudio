@testable import SwiftUMLBridgeFramework
import Testing

@Suite("StateMachineExtractor — edge cases")
struct StateMachineExtractorEdgeCaseTests {

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

    @Test("property without switch-driven transitions yields low-confidence candidate")
    func noSwitchLowConfidence() {
        let source = """
        enum Light { case red, green }
        class Host {
            var state: Light = .red
            func reset() { self.state = .red }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.confidence == .low)
        #expect(models.first?.transitions.allSatisfy { $0.from == "*" } == true)
        #expect(models.first?.notes.contains(where: { $0.contains("No switch statement") }) == true)
    }

    @Test("switch on a different property yields low-confidence candidate")
    func switchOnDifferentPropertyLowConfidence() {
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
        let stateModel = models.first(where: { $0.enumType == "Light" })
        #expect(stateModel != nil)
        #expect(stateModel?.confidence == .low)
        #expect(stateModel?.transitions.allSatisfy { $0.from == "*" } == true)
    }

    @Test("annotated property with switch produces high confidence")
    func annotatedSwitchIsHighConfidence() {
        let source = """
        enum Light { case red, green }
        class Host {
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
        #expect(models.first?.confidence == .high)
        #expect(models.first?.notes.isEmpty == true)
    }

    @Test("inferred type from initializer produces medium confidence")
    func inferredTypeIsMediumConfidence() {
        let source = """
        enum Light { case red, green }
        struct Host {
            @State var state = Light.red
            mutating func toggle() {
                switch self.state {
                case .red: self.state = .green
                case .green: self.state = .red
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.first?.confidence == .medium)
        #expect(models.first?.notes.contains(where: { $0.contains("inferred") }) == true)
    }

    @Test("@Published wrapper with explicit type annotation is detected")
    func publishedWithAnnotationDetected() {
        let source = """
        enum Loading { case idle, busy, done }
        class Store: ObservableObject {
            @Published var state: Loading = .idle
            func start() {
                switch self.state {
                case .idle: self.state = .busy
                case .busy: self.state = .done
                case .done: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.hostType == "Store")
        #expect(models.first?.enumType == "Loading")
    }

    @Test("@State wrapper with inferred type is detected via initializer")
    func stateWrapperWithInferredType() {
        let source = """
        enum Tab { case home, search, profile }
        struct RootView {
            @State var state = Tab.home
            mutating func select() {
                switch self.state {
                case .home: self.state = .search
                case .search: self.state = .profile
                case .profile: self.state = .home
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.hostType == "RootView")
        #expect(models.first?.enumType == "Tab")
        #expect(models.first?.transitions.count == 3)
    }

    @Test("where-clause guard is captured on transition")
    func whereClauseCaptured() {
        let source = """
        enum Flow { case idle, retrying, done }
        class Runner {
            var state: Flow = .idle
            var retryCount: Int = 0
            func tick() {
                switch self.state {
                case .idle where retryCount > 0: self.state = .retrying
                case .idle: self.state = .done
                case .retrying: self.state = .done
                case .done: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        let transitions = models.first?.transitions ?? []
        let guarded = transitions.first(where: { $0.guardText != nil })
        #expect(guarded != nil)
        #expect(guarded?.from == "idle")
        #expect(guarded?.toState == "retrying")
        #expect(guarded?.guardText == "retryCount > 0")
    }

    @Test("actor with TaskState enum is detected")
    func actorTaskState() {
        let source = """
        enum TaskState { case pending, running, succeeded, failed }
        actor Worker {
            var state: TaskState = .pending

            func run() async {
                switch self.state {
                case .pending: self.state = .running
                case .running: self.state = .succeeded
                case .succeeded: break
                case .failed: break
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.hostType == "Worker")
        #expect(models.first?.enumType == "TaskState")
    }

    @Test("NavigationStack route enum is detected")
    func navigationStackRoute() {
        let source = """
        enum Route { case list, detail, settings }
        class Router {
            var state: Route = .list

            func navigate() {
                switch self.state {
                case .list: self.state = .detail
                case .detail: self.state = .settings
                case .settings: self.state = .list
                }
            }
        }
        """
        let models = StateMachineExtractor.extract(from: source)
        #expect(models.count == 1)
        #expect(models.first?.hostType == "Router")
        #expect(models.first?.enumType == "Route")
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
