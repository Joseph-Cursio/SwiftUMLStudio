import Testing
@testable import SwiftUMLBridgeFramework

/// An `#if` among statements is a decision with a branch per clause, and a switch case inside
/// `#if` is a branch of its switch. Code inside `#if` used to make no node at all (#135).
@Suite("ActivityFlowExtractor — #if")
struct ActivityIfConfigTests {

    private func extract(_ source: String) -> ActivityGraph {
        ActivityExtractionFixture.extract(source)
    }

    /// Each edge as `from -label-> to`, naming a node by its label, or by its kind when it has
    /// none (a merge, start or end).
    private func edges(in graph: ActivityGraph) -> Set<String> {
        let names = Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
            (node.id, node.label.trimmingCharacters(in: .whitespaces).isEmpty ? "\(node.kind)" : node.label)
        })
        return Set(graph.edges.map { edge in
            let arrow = edge.label.map { " -\($0)-> " } ?? " -> "
            return "\(names[edge.fromId] ?? "?")\(arrow)\(names[edge.toId] ?? "?")"
        })
    }

    @Test("each clause of an #if is a branch, and a missing #else goes straight to the merge")
    func clausesAreBranches() {
        let graph = extract("""
            class Foo {
                func run() {
                    load()
                    #if DEBUG
                    log()
                    #elseif os(iOS)
                    trace()
                    #endif
                    render()
                }
            }
            """)
        #expect(ActivityExtractionFixture.labels(of: .decision, in: graph) == ["#if"])
        #expect(edges(in: graph) == [
            "start -> load()",
            "load() -> #if",
            "#if -#if DEBUG-> log()",
            "#if -#elseif os(iOS)-> trace()",
            "#if -#else-> merge",
            "log() -> merge",
            "trace() -> merge",
            "merge -> render()",
            "render() -> end"
        ])
    }

    @Test("an #else clause is a branch of its own, and an empty clause goes to the merge")
    func elseClause() {
        let graph = extract("""
            class Foo {
                func run() {
                    #if DEBUG
                    #else
                    trace()
                    #endif
                }
            }
            """)
        #expect(edges(in: graph) == [
            "start -> #if",
            "#if -#if DEBUG-> merge",
            "#if -#else-> trace()",
            "trace() -> merge",
            "merge -> end"
        ])
    }

    @Test("a return inside a clause ends the flow there")
    func returnInClause() {
        let graph = extract("""
            class Foo {
                func run() {
                    #if DEBUG
                    return
                    #else
                    trace()
                    #endif
                }
            }
            """)
        #expect(edges(in: graph).isSuperset(of: ["#if -#if DEBUG-> return", "return -> end"]))
        #expect(!edges(in: graph).contains("return -> merge"))
    }

    @Test("nested #if blocks are nested decisions")
    func nestedIfConfig() {
        let graph = extract("""
            class Foo {
                func run() {
                    #if os(macOS)
                    #if DEBUG
                    log()
                    #endif
                    #endif
                }
            }
            """)
        #expect(ActivityExtractionFixture.labels(of: .decision, in: graph) == ["#if", "#if"])
        #expect(edges(in: graph).contains("#if -#if DEBUG-> log()"))
    }

    @Test("a switch case inside #if is a branch of the switch")
    func switchCaseInIfConfig() {
        let graph = extract("""
            class Foo {
                func run() {
                    switch phase {
                    case .idle: start()
                    #if DEBUG
                    case .running: finish()
                    #if os(iOS)
                    case .paused: resume()
                    #endif
                    #endif
                    default: break
                    }
                }
            }
            """)
        #expect(ActivityExtractionFixture.labels(of: .decision, in: graph) == ["switch phase"])
        #expect(edges(in: graph).isSuperset(of: [
            "switch phase -.idle-> start()",
            "switch phase -.running-> finish()",
            "switch phase -.paused-> resume()",
            "switch phase -default-> break"
        ]))
    }

    @Test("a method declared inside #if is found")
    func methodInIfConfig() {
        let graph = extract("""
            class Foo {
                #if DEBUG
                func run() { log() }
                #endif
            }
            """)
        #expect(ActivityExtractionFixture.labels(of: .action, in: graph) == ["log()"])
    }
}
