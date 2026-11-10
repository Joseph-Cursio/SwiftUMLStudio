import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("NodeInfoTooltip.shortPath")
@MainActor
struct NodeInfoTooltipShortPathTests {

    @Test("returns filename:line for an absolute path")
    func absolutePath() {
        let location = SourceLocation(
            filePath: "/Users/me/Project/Sources/Foo.swift",
            line: 42,
            column: 1
        )
        #expect(NodeInfoTooltip.shortPath(for: location) == "Foo.swift:42")
    }

    @Test("returns filename:line for a relative path")
    func relativePath() {
        let location = SourceLocation(filePath: "Sources/Bar.swift", line: 7, column: 1)
        #expect(NodeInfoTooltip.shortPath(for: location) == "Bar.swift:7")
    }

    @Test("treats a bare filename as the filename component")
    func bareFilename() {
        let location = SourceLocation(filePath: "Baz.swift", line: 1, column: 1)
        #expect(NodeInfoTooltip.shortPath(for: location) == "Baz.swift:1")
    }
}
