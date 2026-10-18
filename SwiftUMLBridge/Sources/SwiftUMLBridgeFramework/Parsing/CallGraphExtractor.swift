import Foundation
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
        let methodName = node.name.canonicalName
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
            let methodName = declRef.baseName.canonicalName
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: callerType, calleeMethod: methodName,
                isAsync: isAsync, isUnresolved: false
            )
        } else {
            // Closure or other complex expression — unresolved
            let rawDesc = calledExpr.singleLineDescription
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
        let methodName = memberAccess.declName.baseName.canonicalName
        guard let base = memberAccess.base else {
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: callerType, calleeMethod: methodName,
                isAsync: isAsync, isUnresolved: false
            )
        }
        // A type written as the receiver, or as what makes it, is named as an extension of it is
        // listed: `Foo<Int>.make()`, `Outer<Int>.Inner.make()`, `[Int].make()` and `Foo<Int>().run()`
        // call into `Foo`, `Outer.Inner`, `Array` and `Foo` (#66). Each name in it reads as Swift
        // reads it, so `` `Plain`.make() `` calls into `Plain` (#123).
        let called = base.as(FunctionCallExprSyntax.self)?.calledExpression
        let baseText: String
        if let typeName = (called ?? base).typeReferenceName {
            baseText = typeName
        } else if let declRef = called?.as(DeclReferenceExprSyntax.self) {
            baseText = declRef.baseName.canonicalName
        } else {
            baseText = base.singleLineDescription
        }
        // `self.refresh()`, or `self().refresh()` through `callAsFunction`. Told from the token, so
        // a comment beside it does not count and `` `self` `` is `self` as well, though
        // `canonicalName` keeps its backticks.
        let isSelf = (called ?? base).as(DeclReferenceExprSyntax.self)?.baseName.expressionName == "self"
        // `Alias.make()` calls into the aliased type (#125).
        let resolvedType: String? = isSelf ? callerType
            : baseText.first?.isUppercase == true ? resolveTypeName(baseText) : nil
        let unresolved = resolvedType == nil && !isSelf
        return CallEdge(
            callerType: callerType, callerMethod: callerMethod,
            calleeType: resolvedType, calleeMethod: methodName,
            isAsync: isAsync, isUnresolved: unresolved
        )
    }

    // MARK: - Static factory

    /// Result of an extraction run
    internal struct ExtractionResult: Sendable {
        let edges: [CallEdge]
        let methods: [String]
    }

    /// Parse `source` and extract all call edges and method definitions. With the project's
    /// `aliases` and the `file` the source was read from, a name written through a typealias is
    /// the aliased type's (#125).
    static func extract(
        from source: String, file: URL? = nil, aliases: TypeAliasResolver = .none
    ) -> ExtractionResult {
        ParsingStack.run {
            let sourceFile = ParsingStack.parse(source, file: file)
            let extractor = CallGraphExtractor(viewMode: .sourceAccurate)
            extractor.resolveTypeName = { aliases.resolve($0, in: file) }
            extractor.walk(sourceFile)
            return ExtractionResult(edges: extractor.edges, methods: Array(extractor.methods).sorted())
        }
    }

    /// Collect every `Type.method` entry point defined across the given source paths.
    static func entryPoints(for paths: [String]) -> [String] {
        let sources = readSources(for: paths)
        let aliases = TypeAliasResolver(sources: sources)
        var allMethods = Set<String>()
        for source in sources {
            allMethods.formUnion(extract(from: source.contents, file: source.file, aliases: aliases).methods)
        }
        return allMethods.sorted()
    }

    /// Every readable Swift file under `paths`, in `FileCollector` order, with its contents.
    static func readSources(for paths: [String]) -> [(file: URL, contents: String)] {
        FileCollector().getFiles(for: paths).compactMap { file in
            (try? String(contentsOf: file, encoding: .utf8)).map { (file, $0) }
        }
    }

    /// An entry point as it was typed in, such as the halves of the CLI's `--entry`, named as
    /// `entryPoints(for:)` lists it: each name, and each component of a dotted type, as Swift
    /// reads it. So `` `Plain`.helper `` is `Plain.helper`, which it calls (#123), and
    /// `Keyed.default` is `` Keyed.`default` ``, as a call written `self.default()` names it (#130).
    static func listedEntryPoint(type: String, method: String) -> (type: String, method: String) {
        (type.canonicalDottedName, method.canonicalMemberIdentifier)
    }
}
