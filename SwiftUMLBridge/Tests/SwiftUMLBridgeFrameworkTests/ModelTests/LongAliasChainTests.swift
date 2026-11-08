import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Swift follows a chain of typealiases to its end, however long, and rejects only a cycle. Each
/// alias step of the lookup used up a level of the depth guard of 8 that ends its cycles, so a
/// chain of 9 links or more stopped partway: the text formats drew an `inherits` edge to the alias
/// it stopped at, which no box declares, and SVG drew no edge (#248). Each case builds with swiftc,
/// which makes the writer conform to `P1`.
@Suite("A long chain of typealiases is followed to its end")
struct LongAliasChainTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let files: [File]
        /// The PlantUML supertype and `ext` lines, in any order.
        let expected: [String]
        /// The SVG edges, by node ids, that must be drawn.
        let svgEdges: [String]
        var extensions = ExtensionVisualization.all

        var testDescription: String { name }
    }

    struct File: Sendable {
        let module: String?
        let source: String
    }

    /// `typealias A<first> = A<first - 1>` … `typealias A<last> = A<last - 1>`, `A0` being `base`,
    /// each with `access` before it.
    static func links(_ range: ClosedRange<Int>, base: String = "P1", access: String = "") -> String {
        range.map { "\(access)typealias A\($0) = \($0 == 1 ? base : "A\($0 - 1)")" }.joined(separator: "\n")
    }

    static func chain(_ length: Int, module: String? = "App") -> Case {
        Case(name: "\(length) links\(module == nil ? ", no module" : "")", files: [
            File(module: module, source: "protocol P1 {}\n\(links(1...length))\nstruct W: A\(length) {}")
        ], expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"])
    }

    static let cases: [Case] = [8, 9, 10, 20, 64, 1_000].map { chain($0) } + [
        chain(20, module: nil),
        Case(name: "each link in its own file", files: [File(module: "App", source: "protocol P1 {}")]
            + (1...12).map { File(module: "App", source: links($0...$0)) }
            + [File(module: "App", source: "struct W: A12 {}")],
             expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"]),
        Case(name: "the chain across two modules", files: [
            File(module: "ModA", source: "public protocol P1 {}\n" + links(1...6, access: "public ")),
            File(module: "ModB", source: "import ModA\n\(links(7...12))\nstruct W: A12 {}")
        ], expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"]),
        Case(name: "the chain in an enclosing type", files: [
            File(module: "App", source: "protocol P1 {}\nenum E {\n\(links(1...12))\nstruct W: A12 {}\n}")
        ], expected: ["P1 <|.. E.W : conforms to"], svgEdges: ["E.W -> P1"]),
        Case(name: "a dotted name through the chain", files: [
            File(module: "App", source: "protocol P1 {}\nenum NS { typealias V = P1 }\n\(links(1...12, base: "NS"))\n"
                + "struct W: A12.V {}")
        ], expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"]),
        Case(name: "an extension spelled through the chain", files: [extended],
             expected: ["P1 <|.. A12 : conforms to", "W <.. A12 : ext"], svgEdges: ["A12 -> P1", "A12 -> W"]),
        Case(name: "an extension spelled through the chain, merged", files: [extended],
             expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"], extensions: .merged),
        Case(name: "a link spelled through its module", files: [
            File(module: "ModA", source: "public protocol P1 {}\n" + links(1...6, access: "public ")),
            File(module: "ModB", source: "import ModA\ntypealias A7 = ModA.A6\n\(links(8...12))\nstruct W: A12 {}")
        ], expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"]),
        Case(name: "a chain from sugar", files: [
            File(module: "App", source: "protocol P1 {}\nextension [Int] { typealias Box = P1 }\n"
                + "\(links(1...12, base: "[Int].Box"))\nstruct W: A12 {}")
        ], expected: ["P1 <|.. W : conforms to"], svgEdges: ["W -> P1"]),
        // Without a module, `A1.Inner` reads no member an extension adds even at one link, as no
        // start is worked out, so only the run with a module shows the chain.
        Case(name: "a member an extension adds to the chain's type", files: [
            File(module: "App", source: "protocol P1 {}\nstruct S1 {}\nextension S1 { typealias Inner = P1 }\n"
                + "\(links(1...12, base: "S1"))\nstruct X: A12.Inner {}")
        ], expected: ["P1 <|.. X : conforms to"], svgEdges: ["X -> P1"], extensions: .merged)
    ] + (["App", nil] as [String?]).map { module in
        Case(name: "a type nested in an extension spelled through the chain\(module == nil ? ", no module" : "")",
             files: [File(module: module, source: "protocol P1 {}\nstruct S1 { typealias Q = P1 }\n"
                + "\(links(1...12, base: "S1"))\nextension A12 { struct Y: Q {} }")],
             expected: ["P1 <|.. A12.Y : conforms to", "S1 <.. A12 : ext"], svgEdges: ["A12.Y -> P1"])
    }

    static let extended = File(
        module: "App", source: "protocol P1 {}\nstruct W {}\n\(links(1...12, base: "W"))\nextension A12: P1 {}"
    )

    /// Each case is read with its files in the order given and reversed, so no answer comes from
    /// which file is read first.
    @Test("the edge ends on the chain's last type", arguments: cases, [false, true])
    func endsOnTheLastType(_ testCase: Case, reversed: Bool) throws {
        let given = testCase.files.map { (module: $0.module, source: $0.source) }
        let ordered = reversed ? given.reversed() : given
        let elements = ElementOptions(showExtensions: testCase.extensions)
        let configuration = Configuration(elements: elements)
        let text = DiagramScript(items: try moduleQualifiedItems(ordered), configuration: configuration).text
        let lines = ["<|", " : ext"].flatMap { ClassDiagramIds.lines(of: text, containing: $0) }
        #expect(Set(lines) == Set(testCase.expected))
        #expect(lines.count == testCase.expected.count)
        let svg = Configuration(elements: elements, format: .svg)
        let graph = LayoutGraphBuilder.buildClassDiagram(from: try moduleQualifiedItems(ordered), configuration: svg)
        for edge in testCase.svgEdges {
            #expect(graph.edgeEnds.contains(edge), "\(edge) in \(graph.edgeEnds)")
        }
    }

    /// A chain is walked in a loop, not a call a link, so on the 512 KB stack Swift Testing gives a
    /// test, as the CLI and Studio give their work, a chain of 1,000 links is followed for an
    /// extension spelled through it, a type nested there, a member read through it, and an entry.
    /// A call a link overflowed this stack at about 150 links in a debug build.
    @Test("a chain of 1,000 links is followed on a cooperative thread's stack")
    func onSmallStack() throws {
        #expect(Thread.current.stackSize <= 1 << 20)
        let source = "protocol P1 {}\nstruct S1 {\n    typealias Q = P1\n    func run() { step() }\n"
            + "    func step() {}\n}\n\(Self.links(1...1_000, base: "S1"))\n"
            + "extension A1000: P1 { struct Y: Q {} }\nstruct X: A1000.Q {}"
        let items = try moduleQualifiedItems([(module: "App", source: source)])
        let text = DiagramScript(items: items, configuration: Configuration()).text
        let lines = ["<|", " : ext"].flatMap { ClassDiagramIds.lines(of: text, containing: $0) }
        #expect(Set(lines) == [
            "P1 <|.. A1000 : conforms to", "S1 <.. A1000 : ext", "P1 <|.. A1000.Y : conforms to",
            "P1 <|.. X : conforms to"
        ])
        let svgItems = try moduleQualifiedItems([(module: "App", source: source)])
        let graph = LayoutGraphBuilder.buildClassDiagram(from: svgItems, configuration: Configuration(format: .svg))
        #expect(Set(graph.edgeEnds).isSuperset(of: ["A1000 -> P1", "A1000 -> S1", "A1000.Y -> P1", "X -> P1"]))
        let (root, paths) = try EntryFixture.written([("Pkg/A.swift", source)])
        defer { try? FileManager.default.removeItem(at: root) }
        for diagram in EntryFixture.both(paths, "A1000", "run") {
            #expect(diagram.contains("step()"))
        }
    }
}
