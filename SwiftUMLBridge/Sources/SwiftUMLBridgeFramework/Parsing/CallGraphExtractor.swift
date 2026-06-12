import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and extracts static call edges from function bodies.
///
/// Resolved callee types:
/// - `self.method()` → same type as caller
/// - `TypeName.method()` (uppercase receiver) → treat as type name
/// - `bareMethod()` → same type as caller
///
/// Unresolved:
/// - `variable.method()` (lowercase receiver) → `isUnresolved = true`, `calleeType = nil`
/// - Closures or complex expressions → `isUnresolved = true`
final class CallGraphExtractor: TypeStackVisitor {
    private var edges: [CallEdge] = []
    private var methods: Set<String> = []
    private var methodStack: [String] = []

    // MARK: - Function declarations (push/pop methodStack)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let methodName = node.name.text
        if let typeName = typeStack.last {
            methods.insert("\(typeName).\(methodName)")
        }
        methodStack.append(methodName)
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { methodStack.removeLast() }

    // MARK: - Function calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callerType = typeStack.last,
              let callerMethod = methodStack.last else { return .visitChildren }

        let isAsync = node.parent?.as(AwaitExprSyntax.self) != nil
        let edge = resolveCallee(node: node, callerType: callerType, callerMethod: callerMethod, isAsync: isAsync)
        edges.append(edge)
        return .visitChildren
    }

    // MARK: - Resolution

    private func resolveCallee(
        node: FunctionCallExprSyntax,
        callerType: String,
        callerMethod: String,
        isAsync: Bool
    ) -> CallEdge {
        let calledExpr = node.calledExpression

        if let memberAccess = calledExpr.as(MemberAccessExprSyntax.self) {
            return resolveMemberAccess(
                memberAccess, callerType: callerType,
                callerMethod: callerMethod, isAsync: isAsync
            )
        } else if let declRef = calledExpr.as(DeclReferenceExprSyntax.self) {
            let methodName = declRef.baseName.text
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: callerType, calleeMethod: methodName,
                isAsync: isAsync, isUnresolved: false
            )
        } else {
            // Closure or other complex expression — unresolved
            let rawDesc = calledExpr.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: nil, calleeMethod: rawDesc,
                isAsync: isAsync, isUnresolved: true
            )
        }
    }

    private func resolveMemberAccess(
        _ memberAccess: MemberAccessExprSyntax,
        callerType: String, callerMethod: String, isAsync: Bool
    ) -> CallEdge {
        let methodName = memberAccess.declName.baseName.text
        guard let base = memberAccess.base else {
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: callerType, calleeMethod: methodName,
                isAsync: isAsync, isUnresolved: false
            )
        }
        let baseText: String
        if let funcCall = base.as(FunctionCallExprSyntax.self),
           let declRef = funcCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            baseText = declRef.baseName.text
        } else {
            baseText = base.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let resolvedType: String? = baseText == "self" ? callerType
            : baseText.first?.isUppercase == true ? baseText : nil
        let unresolved = resolvedType == nil && baseText != "self"
        return CallEdge(
            callerType: callerType, callerMethod: callerMethod,
            calleeType: resolvedType, calleeMethod: methodName,
            isAsync: isAsync, isUnresolved: unresolved
        )
    }

    // MARK: - Static factory

    /// Result of an extraction run
    internal struct ExtractionResult {
        let edges: [CallEdge]
        let methods: [String]
    }

    /// Parse `source` and extract all call edges and method definitions.
    static func extract(from source: String) -> ExtractionResult {
        let sourceFile = Parser.parse(source: source)
        let extractor = CallGraphExtractor(viewMode: .sourceAccurate)
        extractor.walk(sourceFile)
        return ExtractionResult(edges: extractor.edges, methods: Array(extractor.methods).sorted())
    }

    /// Collect every `Type.method` entry point defined across the given source paths.
    static func entryPoints(for paths: [String]) -> [String] {
        let files = FileCollector().getFiles(for: paths)
        var allMethods = Set<String>()
        for file in files {
            if let source = try? String(contentsOf: file, encoding: .utf8) {
                allMethods.formUnion(extract(from: source).methods)
            }
        }
        return allMethods.sorted()
    }
}
