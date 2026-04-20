import Testing
@testable import SwiftUMLBridgeFramework

/// Helpers shared by the split-up activity-extractor test suites.
enum ActivityExtractionFixture {
    static func extract(
        _ source: String, type: String = "Foo", method: String = "run"
    ) -> ActivityGraph {
        ActivityFlowExtractor.extract(from: source, entryType: type, entryMethod: method)
            ?? ActivityGraph()
    }

    static func nodes(
        of kind: ActivityNodeKind, in graph: ActivityGraph
    ) -> [ActivityNode] {
        graph.nodes.filter { $0.kind == kind }
    }

    static func labels(
        of kind: ActivityNodeKind, in graph: ActivityGraph
    ) -> [String] {
        nodes(of: kind, in: graph).map(\.label)
    }
}

@Suite("ActivityFlowExtractor — basics and linear flow")
struct ActivityFlowExtractorTests {

    private func extract(
        _ source: String, type: String = "Foo", method: String = "run"
    ) -> ActivityGraph {
        ActivityExtractionFixture.extract(source, type: type, method: method)
    }

    private func nodes(of kind: ActivityNodeKind, in graph: ActivityGraph) -> [ActivityNode] {
        ActivityExtractionFixture.nodes(of: kind, in: graph)
    }

    // MARK: - Basics

    @Test("missing entry point returns nil")
    func missingEntryReturnsNil() {
        let source = "class Foo { func run() {} }"
        let graph = ActivityFlowExtractor.extract(from: source, entryType: "Bar", entryMethod: "run")
        #expect(graph == nil)
    }

    @Test("empty function body yields start → end with no actions")
    func emptyBodyYieldsStartEnd() {
        let graph = extract("class Foo { func run() {} }")
        #expect(nodes(of: .start, in: graph).count == 1)
        #expect(nodes(of: .end, in: graph).count == 1)
        #expect(nodes(of: .action, in: graph).isEmpty)
        let start = graph.startNode!
        let startEdges = graph.outgoingEdges(from: start.id)
        #expect(startEdges.count == 1)
    }

    @Test("single expression emits a single action node")
    func singleExpressionEmitsAction() {
        let graph = extract("""
        class Foo {
            func run() { doThing() }
        }
        """)
        #expect(nodes(of: .action, in: graph).count == 1)
    }

    // MARK: - Decisions (if / guard)

    @Test("if/else produces decision + merge with labeled branches")
    func ifElseProducesDecisionAndMerge() {
        let graph = extract("""
        class Foo {
            func run() {
                if flag {
                    doThen()
                } else {
                    doElse()
                }
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count == 1)
        #expect(nodes(of: .merge, in: graph).count == 1)
        let branchLabels = Set(graph.edges.compactMap(\.label))
        #expect(branchLabels.contains("true"))
        #expect(branchLabels.contains("false"))
    }

    @Test("if without else has a false branch to merge")
    func ifWithoutElseFalseBranch() {
        let graph = extract("""
        class Foo {
            func run() {
                if flag { doThen() }
                after()
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count == 1)
        let branchLabels = Set(graph.edges.compactMap(\.label))
        #expect(branchLabels.contains("false"))
    }

    @Test("else-if chain produces nested decisions")
    func elseIfChainNestsDecisions() {
        let graph = extract("""
        class Foo {
            func run() {
                if a {
                    one()
                } else if b {
                    two()
                } else {
                    three()
                }
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count >= 2)
    }

    @Test("guard emits decision whose false branch reaches end")
    func guardFalseBranchReachesEnd() {
        let graph = extract("""
        class Foo {
            func run() {
                guard precondition else { return }
                doThing()
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count == 1)
        let endId = graph.nodes.first(where: { $0.kind == .end })!.id
        let returnNode = graph.nodes.first(where: {
            $0.kind == .action && $0.label.contains("return")
        })
        #expect(returnNode != nil)
        let terminalEdges = graph.edges.filter { $0.toId == endId }
        #expect(terminalEdges.count >= 1)
    }

    // MARK: - Switch

    @Test("switch creates decision with one edge per case")
    func switchEmitsBranchesPerCase() {
        let graph = extract("""
        class Foo {
            func run() {
                switch tag {
                case .red: red()
                case .green: green()
                case .blue: blue()
                }
            }
        }
        """)
        #expect(nodes(of: .decision, in: graph).count == 1)
        let switchLabel = ActivityExtractionFixture.labels(of: .decision, in: graph).first ?? ""
        #expect(switchLabel.contains("switch"))
        let caseEdgeLabels = graph.edges.compactMap(\.label).filter { $0.contains(".") }
        #expect(caseEdgeLabels.count >= 3)
    }

    @Test("switch with default produces default-labeled branch")
    func switchWithDefaultBranchLabel() {
        let graph = extract("""
        class Foo {
            func run() {
                switch tag {
                case .red: red()
                default: other()
                }
            }
        }
        """)
        let labels = Set(graph.edges.compactMap(\.label))
        #expect(labels.contains("default"))
    }

    // MARK: - Return / throw

    @Test("return emits a terminal action going to end")
    func returnRoutesToEnd() {
        let graph = extract("""
        class Foo {
            func run() -> Int { return 42 }
        }
        """)
        let endId = graph.nodes.first(where: { $0.kind == .end })!.id
        let returnEdges = graph.edges.filter { $0.toId == endId }
        #expect(!returnEdges.isEmpty)
    }

    @Test("throw emits a terminal action going to end")
    func throwRoutesToEnd() {
        let graph = extract("""
        class Foo {
            func run() throws { throw SomeError.bad }
        }
        """)
        let throwAction = graph.nodes.first(where: {
            $0.kind == .action && $0.label.contains("throw")
        })
        #expect(throwAction != nil)
    }
}
