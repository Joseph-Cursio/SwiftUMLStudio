import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and collects all `import` statement edges.
final class ImportExtractor: SyntaxVisitor {
    private var edges: [ImportEdge] = []
    private let sourceModule: String

    private init(sourceModule: String) {
        self.sourceModule = sourceModule
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map { $0.name.canonicalName }.joined(separator: ".")
        if !moduleName.isEmpty {
            edges.append(ImportEdge(sourceModule: sourceModule, importedModule: moduleName))
        }
        return .skipChildren
    }

    // MARK: - Static factory

    /// Parse `source` and extract all import edges, using `sourceModule` as the module label.
    static func extract(from source: String, sourceModule: String) -> [ImportEdge] {
        ParsingStack.run {
            let sourceFile = Parser.parse(source: source)
            let extractor = ImportExtractor(sourceModule: sourceModule)
            extractor.walk(sourceFile)
            return extractor.edges
        }
    }
}
