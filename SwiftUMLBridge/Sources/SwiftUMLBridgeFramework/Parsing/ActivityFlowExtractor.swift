import Foundation
import SwiftParser
import SwiftSyntax

/// Walks the body of a specific entry function and emits an `ActivityGraph`
/// of control-flow nodes (actions, decisions, forks/joins, loops) and edges.
///
/// Supported Swift constructs:
/// - `if`/`guard` → decision nodes with `"true"`/`"false"` branches
/// - `switch` → decision with one branch per case
/// - `for`/`while`/`repeat` → loop nodes with back-edges
/// - `return`/`throw` → terminal edges to the end node
/// - `do`/`catch` → decision branching into catch bodies
/// - `async let` → fork/join pair (one branch per binding)
/// - `withTaskGroup` / `withThrowingTaskGroup` + `group.addTask { … }` → fork/join
///   with each task closure as a concurrent branch
public enum ActivityFlowExtractor {
    /// Extract an activity graph for the given entry point from the provided source.
    /// Returns `nil` if the entry point is not found in the source.
    public static func extract(
        from source: String,
        entryType: String,
        entryMethod: String
    ) -> ActivityGraph? {
        let sourceFile = Parser.parse(source: source)
        let finder = ActivityEntryFunctionFinder(viewMode: .sourceAccurate)
        finder.entryType = entryType
        finder.entryMethod = entryMethod
        finder.walk(sourceFile)
        guard let body = finder.foundBody else { return nil }

        var builder = ActivityGraphBuilder()
        return builder.build(body: body, entryType: entryType, entryMethod: entryMethod)
    }
}

// MARK: - Entry Function Finder

/// Locates the `CodeBlockSyntax` body of a function whose enclosing type matches
/// `entryType` and whose name matches `entryMethod`.
final class ActivityEntryFunctionFinder: SyntaxVisitor {
    var entryType: String = ""
    var entryMethod: String = ""
    var foundBody: CodeBlockSyntax?
    private var typeStack: [String] = []

    // MARK: Type declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.extendedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        typeStack.append(typeName)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        if !typeStack.isEmpty { typeStack.removeLast() }
    }

    // MARK: Function declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if foundBody == nil,
           typeStack.last == entryType,
           node.name.text == entryMethod,
           let body = node.body {
            foundBody = body
        }
        return .skipChildren
    }
}
