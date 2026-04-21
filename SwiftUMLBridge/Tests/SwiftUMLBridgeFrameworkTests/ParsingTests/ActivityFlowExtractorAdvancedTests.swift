import Testing
@testable import SwiftUMLBridgeFramework

@Suite("ActivityFlowExtractor — loops, do/catch, concurrency")
struct ActivityFlowExtractorAdvancedTests {

    private func extract(
        _ source: String, type: String = "Foo", method: String = "run"
    ) -> ActivityGraph {
        ActivityExtractionFixture.extract(source, type: type, method: method)
    }

    private func nodes(of kind: ActivityNodeKind, in graph: ActivityGraph) -> [ActivityNode] {
        ActivityExtractionFixture.nodes(of: kind, in: graph)
    }

    // MARK: - Loops

    @Test("for loop emits loopStart with back-edge")
    func forLoopEmitsLoopStart() {
        let graph = extract("""
        class Foo {
            func run() {
                for item in items {
                    process(item)
                }
            }
        }
        """)
        #expect(nodes(of: .loopStart, in: graph).count == 1)
        let loopStart = nodes(of: .loopStart, in: graph).first!
        let backEdges = graph.edges.filter {
            $0.toId == loopStart.id && $0.fromId != loopStart.id
        }
        #expect(backEdges.isEmpty == false)
    }

    @Test("while loop emits loopStart")
    func whileLoopEmitsLoopStart() {
        let graph = extract("""
        class Foo {
            func run() {
                while condition { tick() }
            }
        }
        """)
        #expect(nodes(of: .loopStart, in: graph).count == 1)
    }

    @Test("repeat-while emits loopStart at the tail")
    func repeatWhileEmitsLoopStart() {
        let graph = extract("""
        class Foo {
            func run() {
                repeat { tick() } while keepGoing
            }
        }
        """)
        #expect(nodes(of: .loopStart, in: graph).count == 1)
    }

    // MARK: - Do / catch

    @Test("do/catch emits decision branching into catch")
    func doCatchProducesDecision() {
        let graph = extract("""
        class Foo {
            func run() {
                do {
                    try risky()
                } catch let error {
                    handle(error)
                }
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count == 1)
        let labels = Set(graph.edges.compactMap(\.label))
        #expect(labels.contains("success"))
        #expect(labels.contains { $0.hasPrefix("catch") })
    }

    @Test("do without catch is just a scoped block")
    func doWithoutCatchNoDecision() {
        let graph = extract("""
        class Foo {
            func run() {
                do { inner() }
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).isEmpty)
    }

    // MARK: - Async let (concurrency)

    @Test("async let emits fork/join pair")
    func asyncLetEmitsForkJoin() {
        let graph = extract("""
        class Foo {
            func run() async {
                async let a = fetchA()
                async let b = fetchB()
                _ = await (a, b)
            }
        }
        """)
        #expect(nodes(of: .fork, in: graph).isEmpty == false)
        #expect(nodes(of: .join, in: graph).isEmpty == false)
        let asyncActions = graph.nodes.filter { $0.kind == .action && $0.isAsync }
        #expect(asyncActions.count >= 2)
    }

    // MARK: - TaskGroup (concurrency)

    @Test("withTaskGroup + addTask emits fork/join with one branch per task")
    func taskGroupEmitsForkJoin() {
        let graph = extract("""
        class Foo {
            func run() async {
                await withTaskGroup(of: Int.self) { group in
                    group.addTask { await fetchOne() }
                    group.addTask { await fetchTwo() }
                    group.addTask { await fetchThree() }
                }
            }
        }
        """)
        #expect(nodes(of: .fork, in: graph).count == 1)
        #expect(nodes(of: .join, in: graph).count == 1)
        let fork = nodes(of: .fork, in: graph).first!
        let forkOut = graph.outgoingEdges(from: fork.id)
        #expect(forkOut.count >= 3)
    }

    @Test("withThrowingTaskGroup is recognised as a task group")
    func throwingTaskGroupEmitsForkJoin() {
        let graph = extract("""
        class Foo {
            func run() async throws {
                try await withThrowingTaskGroup(of: Int.self) { group in
                    group.addTask { try await fetchA() }
                    group.addTask { try await fetchB() }
                }
            }
        }
        """)
        #expect(nodes(of: .fork, in: graph).count == 1)
        #expect(nodes(of: .join, in: graph).count == 1)
    }

    @Test("taskGroup with no addTask falls back to a plain action")
    func taskGroupWithoutAddTaskFallsBack() {
        let graph = extract("""
        class Foo {
            func run() async {
                await withTaskGroup(of: Int.self) { group in
                    log("empty group")
                }
            }
        }
        """)
        #expect(nodes(of: .fork, in: graph).isEmpty)
        #expect(nodes(of: .action, in: graph).isEmpty == false)
    }

    // MARK: - Await (outside task groups)

    @Test("await foo() emits an async action")
    func awaitEmitsAsyncAction() {
        let graph = extract("""
        class Foo {
            func run() async {
                await fetch()
            }
        }
        """)
        let asyncActions = graph.nodes.filter { $0.kind == .action && $0.isAsync }
        #expect(asyncActions.count == 1)
    }

    // MARK: - Extensions and actors

    @Test("entry function inside an extension is discovered")
    func extensionEntryDiscovered() {
        let graph = extract("""
        class Foo {}
        extension Foo {
            func run() { doThing() }
        }
        """)
        #expect(nodes(of: .action, in: graph).isEmpty == false)
    }

    @Test("entry function inside an actor is discovered")
    func actorEntryDiscovered() {
        let graph = extract("""
        actor Foo {
            func run() { doThing() }
        }
        """)
        #expect(nodes(of: .action, in: graph).isEmpty == false)
    }
}
