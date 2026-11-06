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
    private var entryMethods: Set<String> = []
    private var nestedEntryMethods: [String: String] = [:]
    private var methodStack: [String] = []

    // MARK: - Function declarations (push/pop methodStack)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let methodName = node.name.canonicalName
        if let typeName = typeStack.last {
            methods.insert("\(typeName).\(methodName)")
            if node.body != nil, !node.isInsideBody {
                if typeStack.count == 1 {
                    entryMethods.insert("\(typeName).\(methodName)")
                } else {
                    nestedEntryMethods["\(typeName).\(methodName)"] = typeName
                    nestedEntryMethods["\(typeStack.joined(separator: ".")).\(methodName)"] = typeName
                }
            }
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
        /// The methods an entry through several types can mean in a type that is in no other, as
        /// `Type.method`: a body's, or an extension's under the type it names, which may be dotted
        /// (`OB.IB.run`). A requirement has no body, a function local to a body is no member, and a
        /// type local to a body cannot be named from outside it, so none of those is here.
        let entryMethods: Set<String>
        /// The same for a type inside another, which is filed under its innermost name: its
        /// `Type.method` under that name (`IB.run`) and under the types around it (`OB.IB.run`), to
        /// the name (`IB`).
        let nestedEntryMethods: [String: String]
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
            return ExtractionResult(
                edges: extractor.edges, methods: Array(extractor.methods).sorted(),
                entryMethods: extractor.entryMethods, nestedEntryMethods: extractor.nestedEntryMethods
            )
        }
    }

    /// What an entry typed as `name`, which can come to any of `types`
    /// (`TypeAliasResolver.entryTypes(of:)`), is drawn from: the only one, or of several the first
    /// with a body for `method`, as that method is filed, and `nil` when none has one. Sequence and
    /// activity diagrams both choose here, so they cannot disagree on the type. A body counts
    /// however little it does: a `run` with no calls is still that type's. Of one spelling, what is
    /// filed under it wins, so `extension OB.IB` is `OB.IB` whichever file is read first. A nested
    /// type is only what its whole spelling names, or failing every type, what `name` itself was
    /// typed as: `IB` from a typealias is the top-level `IB`, not `OC.IB`. `results` are in the
    /// order the files were read, and a single type needs none of them, so a name that is no
    /// typealias is parsed no more for being chosen.
    static func entryType(
        named name: String, among types: [String], method: String,
        in results: @autoclosure () -> [ExtractionResult]
    ) -> String? {
        guard types.count > 1 else { return types.first }
        var filed: Set<String> = []
        var nested: [String: String] = [:]
        for result in results() {
            filed.formUnion(result.entryMethods)
            nested.merge(result.nestedEntryMethods) { first, _ in first }
        }
        for type in types {
            if filed.contains("\(type).\(method)") { return type }
            if type.contains("."), let nestedType = nested["\(type).\(method)"] { return nestedType }
        }
        return nested["\(name).\(method)"]
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
