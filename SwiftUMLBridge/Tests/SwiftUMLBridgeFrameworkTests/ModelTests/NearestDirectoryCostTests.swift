import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

private typealias Fixture = NearestDirectoryFixture

@Suite("Ranking by directory stays quick")
struct NearestDirectoryCostTests {

    /// The bound is for a debug build, by this thread's CPU clock, so suites running beside this
    /// one do not count (8e939be). Each writer's scan is one comparison per candidate, not a
    /// split of each path, which took seconds; the memo shares the candidates among directories.
    private func cpuSeconds(_ work: () throws -> Void) rethrows -> Double {
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        try work()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }

    @Test("many writers among many same-named types in many directories")
    func manyWritersAmongManyCandidates() throws {
        let root = "/Users/someone/Developer/a/rather/long/path/to/the/project/Sources"
        let files: [Fixture.File] = (0..<400).flatMap { index in
            [
                ("\(root)/Dir\(index)/Base.swift", "class Base {}"),
                ("\(root)/Dir\(index)/Sub.swift", "class Sub\(index): Base {}"),
            ]
        }
        let items = try Fixture.parsed(files)
        var svg: [String] = []
        let svgTime = cpuSeconds {
            svg = LayoutGraphBuilder.buildClassDiagram(from: items, configuration: Configuration(format: .svg))
                .edges.map { "\($0.sourceId) -> \($0.targetId)" }
        }
        #expect(svgTime < 2, "\(svgTime)")
        #expect(svg.contains("Sub7 -> Base_7"))
        var text = ""
        let textTime = cpuSeconds {
            text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        }
        #expect(textTime < 2, "\(textTime)")
        #expect(text.contains("Base6 <|-- Sub7 : inherits"))
    }

    /// Each writer in a directory of its own, all 400 candidates equally near it, so each scan
    /// reads every candidate's module directory for an import (#233): half the writers import
    /// one of them, the last read, and half import nothing any directory names.
    @Test("many writers among many same-named types equally near, with imports")
    func manyWritersAmongTiedCandidates() throws {
        let root = "/Users/someone/Developer/a/rather/long/path/to/the/project/Sources"
        let files: [Fixture.File] = (0..<400).map { ("\(root)/Dir\($0)/Base.swift", "public class Base {}") }
            + (0..<400).map { index in
                let imported = index.isMultiple(of: 2) ? "Dir399" : "Elsewhere"
                let source = "import Foundation\nimport \(imported)\nclass Sub\(index): Base {}"
                return ("\(root)/Writer\(index)/Sub.swift", source)
            }
        let items = try Fixture.parsed(files)
        var text = ""
        let elapsed = cpuSeconds {
            text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        }
        #expect(elapsed < 2, "\(elapsed)")
        #expect(text.contains("Base398 <|-- Sub0 : inherits"))
        #expect(text.contains("Base <|-- Sub1 : inherits"))
    }

    /// 600 directories, each with a chain of typealiases through a type's members, every link in
    /// a sibling of the last's directory, so no two links of a chain share an answer.
    @Test("many alias chains across sibling directories")
    func manyChainsAcrossSiblingDirectories() throws {
        let members = (1..<8).map { "    typealias A\($0) = \($0 == 7 ? "Proto" : "NS.A\($0 + 1)")" }
            .joined(separator: "\n")
        let files: [Fixture.File] = (0..<600).flatMap { index in
            [
                ("/r/Dir\(index)/Alias/Alias.swift", "typealias A0 = NS.A1"),
                ("/r/Dir\(index)/NS/NS.swift", "struct NS {\n\(members)\n}"),
                ("/r/Dir\(index)/Proto/Proto.swift", "protocol Proto {}"),
            ]
        } + [("/r/Dir0/Writer/Writer.swift", "struct Writer: A0 {}")]
        let items = try Fixture.parsed(files)
        var text = ""
        let elapsed = cpuSeconds {
            text = DiagramScript(items: items, configuration: Configuration(format: .plantuml)).text
        }
        #expect(elapsed < 2, "\(elapsed)")
        #expect(text.contains("<|.. Writer : conforms to"))
    }
}
