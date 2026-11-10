@testable import SwiftUMLBridgeFramework
import Testing

// The directory tier (`NearestDirectoryTests`, #78) wherever a name is looked up: every format, a
// merged extension, a hidden type, a typealias, and the memo the text formats share.

/// Files with paths of their own, parsed from strings, for the suites of the directory tier.
enum NearestDirectoryFixture {
    typealias File = (path: String, source: String)

    static func parsed(_ files: [File]) throws -> [SyntaxStructure] {
        try files.flatMap { file in
            let items = try #require(SyntaxStructure.create(from: file.source)?.substructure)
            func stamp(_ item: SyntaxStructure) {
                item.sourceLocation = SourceLocation(filePath: file.path, line: 1, column: 1)
                item.substructure?.forEach(stamp)
            }
            items.forEach(stamp)
            return items
        }
    }

    static func edges(_ files: [File], _ elements: ElementOptions = ElementOptions()) throws -> [String] {
        LayoutGraphBuilder.buildClassDiagram(
            from: try parsed(files), configuration: Configuration(elements: elements, format: .svg)
        )
        .edges
        .map { "\($0.sourceId) -> \($0.targetId)" }
    }

    static func lines(
        _ files: [File], _ format: DiagramFormat, _ elements: ElementOptions = ElementOptions()
    ) throws -> [String] {
        DiagramScript(items: try parsed(files), configuration: Configuration(elements: elements, format: format))
            .text.split(separator: "\n").map(String.init)
    }
}
