@testable import SwiftUMLBridgeFramework
import Testing

// An `#if` block's clauses are read like the rest of the type, as the class diagram reads them
// (#135). Most tests run their source as written (`ifConfig → true`) and with every `#if`
// replaced by its first clause (`ifConfig → false`), which is the file the compiler sees when
// each condition holds. The second case is the control.

@Suite("State-machine declarations inside #if are read")
struct IfConfigStateMachineTests {

    @Test("an assignment repeated in each #if clause is one transition", arguments: [true, false])
    func transitionInEachClause(ifConfig: Bool) throws {
        let machine = try #require(StateMachineExtractor.extract(from: source("""
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        #if DEBUG
                        print("debug: back to red")
                        state = .red
                        #else
                        state = .red
                        #endif
                    }
                }
            }
            """, ifConfig: ifConfig)).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> red"])
    }

    @Test("an assignment repeated in both branches of an if is one transition")
    func transitionInEachIfBranch() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                var verbose = false
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        if verbose {
                            print("back to red")
                            state = .red
                        } else {
                            state = .red
                        }
                    }
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> red"])
    }

    @Test("different assignments in the clauses are each a transition")
    func differentTransitionsInClauses() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        #if DEBUG
                        state = .green
                        #else
                        state = .red
                        #endif
                    }
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> green", "amber -> red"])
    }

    @Test("a repeated assignment with no switch is one transition")
    func unknownSourceTransitionInEachClause() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Phase { case idle, running }
            final class Job {
                var phase: Phase = .idle
                func start() {
                    #if DEBUG
                    phase = .running
                    #else
                    phase = .running
                    #endif
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" } == ["* -> running"])
    }

    @Test("an enum case inside #if is a state", arguments: [true, false])
    func enumCaseInIfConfig(ifConfig: Bool) throws {
        let machine = try #require(StateMachineExtractor.extract(from: source("""
            enum Phase {
                case idle, running
                #if DEBUG
                case done
                #else
                case done
                #endif
            }
            final class Job {
                var phase: Phase = .idle
                func step() {
                    switch phase {
                    case .idle: phase = .running
                    #if DEBUG
                    case .running: phase = .done
                    #endif
                    default: break
                    }
                }
            }
            """, ifConfig: ifConfig)).first)
        let states = machine.states.map { "\($0.name)\($0.isInitial ? " initial" : "")\($0.isFinal ? " final" : "")" }
        #expect(states == ["idle initial", "running", "done final"])
    }

    @Test("an enum case with associated values inside #if still rejects the enum", arguments: [true, false])
    func associatedValueCaseInIfConfig(ifConfig: Bool) {
        let machines = StateMachineExtractor.extract(from: source("""
            enum Phase {
                case idle, running
                #if DEBUG
                case failed(String)
                #endif
            }
            final class Job {
                var phase: Phase = .idle
                func step() {
                    switch phase {
                    case .idle: phase = .running
                    case .running: phase = .idle
                    #if DEBUG
                    case .failed: phase = .idle
                    #endif
                    }
                }
            }
            """, ifConfig: ifConfig)).map(\.identifier)
        #expect(machines.isEmpty)
    }
}
