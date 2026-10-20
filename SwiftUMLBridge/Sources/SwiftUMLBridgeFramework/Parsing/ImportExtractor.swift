import Foundation
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

    /// The modules `sourceFile` imports anywhere at file scope, in any branch of an `#if`, each by
    /// the first component of its path: `ModA` for `import ModA`, `import struct ModA.Foo` and
    /// `import ModA.Sub`.
    static func importedModules(in sourceFile: SourceFileSyntax) -> Set<String> {
        importedModules(in: sourceFile, exportedOnly: false)
    }

    /// The modules `sourceFile` re-exports with `@_exported import`, read as
    /// `importedModules(in:)` reads them. Swift lets every file of the module, and every file
    /// that imports it, see their declarations (`ModuleReexports`).
    static func reexportedModules(in sourceFile: SourceFileSyntax) -> Set<String> {
        importedModules(in: sourceFile, exportedOnly: true)
    }

    private static func importedModules(in sourceFile: SourceFileSyntax, exportedOnly: Bool) -> Set<String> {
        var modules: Set<String> = []
        func collect(_ statements: CodeBlockItemListSyntax) {
            for statement in statements {
                if let importDecl = statement.item.as(ImportDeclSyntax.self), let first = importDecl.path.first {
                    guard !exportedOnly || isExported(importDecl) else { continue }
                    modules.insert(first.name.canonicalName)
                } else if let ifConfig = statement.item.as(IfConfigDeclSyntax.self) {
                    for clause in ifConfig.clauses {
                        if case .statements(let nested)? = clause.elements { collect(nested) }
                    }
                }
            }
        }
        collect(sourceFile.statements)
        return modules
    }

    private static func isExported(_ importDecl: ImportDeclSyntax) -> Bool {
        importDecl.attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
        }
    }

    /// Parse `source`, read from `file` when there is one, and extract all import edges, using
    /// `sourceModule` as the module label.
    static func extract(from source: String, sourceModule: String, file: URL? = nil) -> [ImportEdge] {
        ParsingStack.run {
            let sourceFile = ParsingStack.parse(source, file: file)
            let extractor = ImportExtractor(sourceModule: sourceModule)
            extractor.walk(sourceFile)
            return extractor.edges
        }
    }
}
