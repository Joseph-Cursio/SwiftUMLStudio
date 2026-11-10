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
    private var bodies: [CallBody] = []
    private var methodStack: [String] = []
    /// The `CallBody.identifier` of each function `methodStack` names.
    private var bodyStack: [String] = []
    /// The file being read, which with a position tells one declaration from every other.
    private var file: URL?

    // MARK: - Function declarations (push/pop methodStack)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let methodName = node.name.canonicalName
        let offset = node.positionAfterSkippingLeadingTrivia.utf8Offset
        if let typeName = typeStack.last, node.body != nil {
            // Only a member, of a type that can be named, can be an entry: a function local to a
            // body is no member, a type local to a body cannot be named from outside it, and a
            // protocol requirement has nothing to draw (#234, #235).
            let isNameable = node.isMember && !node.isInsideBody
            if isNameable { methods.insert("\(typeName).\(methodName)") }
            bodies.append(CallBody(
                file: file, offset: offset, type: typeName, path: typeStack.joined(separator: "."),
                depth: typeStack.count, method: methodName,
                parameters: node.signature.parameterClause.parameters.map {
                    CallParameter(
                        label: $0.firstName.canonicalName, hasDefault: $0.defaultValue != nil,
                        isVariadic: $0.ellipsis != nil
                    )
                },
                isNameable: isNameable,
                localType: localTypeIdentifier(around: node)
            ))
        }
        methodStack.append(methodName)
        bodyStack.append(CallBody.identifier(file: file, offset: offset))
        return .visitChildren
    }
    override func visitPost(_: FunctionDeclSyntax) {
        methodStack.removeLast()
        bodyStack.removeLast()
    }

    /// The type local to a body nearest around `node`, when the type nearest around it is one.
    private func localTypeIdentifier(around node: some SyntaxProtocol) -> String? {
        guard let type = node.enclosingTypeDeclaration, type.isInsideBody else { return nil }
        return CallBody.identifier(file: file, offset: type.positionAfterSkippingLeadingTrivia.utf8Offset)
    }

    // MARK: - Function calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callerType = typeStack.last,
              let callerMethod = methodStack.last else { return .visitChildren }

        let isAsync = node.parent?.as(AwaitExprSyntax.self) != nil
        var edge = resolveCallee(node: node, callerType: callerType, callerMethod: callerMethod, isAsync: isAsync)
        edge.callerBody = bodyStack.last
        if node.trailingClosure == nil, node.additionalTrailingClosures.isEmpty {
            edge.argumentLabels = node.arguments.map { $0.label?.canonicalName ?? "_" }
        }
        if !edge.isUnresolved { locateCallee(of: &edge, at: node) }
        edges.append(edge)
        return .visitChildren
    }

    /// Which body a resolved call reaches, where the name alone cannot say (#235). A bare call
    /// reaches a function local to a body around it before any member. A call to `self` in a
    /// member of a type local to a body reaches that type's members, and so does a call through
    /// the name of a type a body around it declares. Any other reaches a member that can be named.
    private func locateCallee(of edge: inout CallEdge, at node: FunctionCallExprSyntax) {
        let called = node.calledExpression
        if let bare = called.as(DeclReferenceExprSyntax.self) {
            if let local = node.localFunction(named: bare.baseName.canonicalName) {
                edge.calleeBody = CallBody.identifier(
                    file: file, offset: local.positionAfterSkippingLeadingTrivia.utf8Offset
                )
                return
            }
        }
        if edge.calleeType == edge.callerType, isSelfCall(called) {
            edge.calleeLocalType = localTypeIdentifier(around: node)
        } else if let calleeType = edge.calleeType, let local = node.localType(named: calleeType) {
            edge.calleeLocalType = CallBody.identifier(
                file: file, offset: local.positionAfterSkippingLeadingTrivia.utf8Offset
            )
        }
    }

    /// Whether `called` calls into `self`: a bare name, `.name`, `self.name` or `self().name`.
    private func isSelfCall(_ called: ExprSyntax) -> Bool {
        if called.is(DeclReferenceExprSyntax.self) { return true }
        guard let member = called.as(MemberAccessExprSyntax.self) else { return false }
        guard let base = member.base else { return true }
        let receiver = base.as(FunctionCallExprSyntax.self)?.calledExpression ?? base
        return receiver.as(DeclReferenceExprSyntax.self)?.baseName.expressionName == "self"
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
        }
        if let declRef = calledExpr.as(DeclReferenceExprSyntax.self) {
            let methodName = declRef.baseName.canonicalName
            return CallEdge(
                callerType: callerType, callerMethod: callerMethod,
                calleeType: callerType, calleeMethod: methodName,
                isAsync: isAsync, isUnresolved: false
            )
        }
        // Closure or other complex expression — unresolved
        let rawDesc = calledExpr.singleLineDescription
        return CallEdge(
            callerType: callerType, callerMethod: callerMethod,
            calleeType: nil, calleeMethod: rawDesc,
            isAsync: isAsync, isUnresolved: true
        )
    }

    private func resolveMemberAccess(
        _ memberAccess: MemberAccessExprSyntax,
        callerType: String,
        callerMethod: String,
        isAsync: Bool
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
        /// Every function with a body in a type, in the order it is written, which calls are
        /// filed under.
        let bodies: [CallBody]
    }

    /// Parse `source` and extract all call edges and method definitions. With the project's
    /// `aliases` and the `file` the source was read from, a name written through a typealias is
    /// the aliased type's (#125).
    static func extract(
        from source: String, file: URL? = nil, aliases: TypeAliasResolver = .withoutProject
    ) -> ExtractionResult {
        ParsingStack.run {
            let sourceFile = ParsingStack.parse(source, file: file)
            let extractor = CallGraphExtractor(viewMode: .sourceAccurate)
            extractor.file = file
            extractor.resolveTypeName = { aliases.resolve($0, in: file) }
            extractor.walk(sourceFile)
            return ExtractionResult(
                edges: extractor.edges, methods: Array(extractor.methods).sorted(), bodies: extractor.bodies
            )
        }
    }

    /// The one body an entry typed as `name.method`, where `name` can come to any of `types`
    /// (`TypeAliasResolver.entryTypes(of:)`), is drawn from, and `nil` when none is. Sequence and
    /// activity diagrams both start from it, so they draw the same code (#235). A body counts
    /// however little it does: a `run` with no calls is still that type's. Only a member that can
    /// be named from outside a body counts, so not a function local to a body, nor a member of a
    /// type local to one. Each of `types` in turn: a top-level type's body or an extension filed
    /// under that spelling, so `extension OB.IB` is `OB.IB` whichever file is read first, then a
    /// nested type whose whole spelling it is, so `OB.IB.run` is the `run` of an `IB` declared
    /// inside `OB`. Failing every type, a nested type of the innermost name `name` was typed as,
    /// which is how the entry list offers it: `IB` from a typealias is the top-level `IB`, not
    /// `OC.IB` (#234). Where several bodies are met, as overloads, or as same-named nested types,
    /// the first is drawn, in the order the files were read and the code is written in each.
    static func entryBody(
        named name: String, among types: [String], method: String, in bodies: [CallBody]
    ) -> CallBody? {
        let named = bodies.filter { $0.isNameable && $0.method == method }
        for type in types {
            if let body = named.first(where: { $0.depth == 1 && $0.path == type }) { return body }
            if let body = named.first(where: { $0.depth > 1 && $0.path == type }) { return body }
        }
        return named.first { $0.depth > 1 && ($0.type == name || $0.path == name) }
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
