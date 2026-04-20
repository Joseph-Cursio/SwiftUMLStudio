import Foundation
import SwiftSyntax

/// Incrementally constructs an `ActivityGraph` by walking a function body and
/// emitting nodes + edges for each control-flow construct.
///
/// The walker threads two pieces of state through recursive calls:
/// - `entry`: the first node id of the just-walked fragment (or `nil` if the fragment emitted nothing).
/// - `exits`: open-ended node ids whose outgoing edges still need to be wired by the caller.
///
/// Terminal statements (`return`/`throw`) link directly to the shared `end` node and return `exits: []`.
struct ActivityGraphBuilder {

    // MARK: - Collected graph state

    var nodes: [ActivityNode] = []
    var edges: [ActivityEdge] = []
    var nextId: Int = 0
    /// Shared terminal end node; `return`/`throw` route here directly.
    var endNodeId: Int = -1

    /// Result of walking a statement or block.
    struct WalkResult {
        /// First node of the walked fragment, or `nil` when nothing was emitted.
        let entry: Int?
        /// Node ids whose outgoing edge has not yet been wired.
        let exits: [Int]
    }

    // MARK: - Public build entry point

    mutating func build(
        body: CodeBlockSyntax,
        entryType: String,
        entryMethod: String
    ) -> ActivityGraph {
        let startId = makeNode(kind: .start, label: "")
        let endId = makeNode(kind: .end, label: "")
        endNodeId = endId

        let result = walkBlock(body.statements)
        if let entry = result.entry {
            addEdge(from: startId, to: entry)
        } else {
            addEdge(from: startId, to: endId)
        }
        for exit in result.exits {
            addEdge(from: exit, to: endId)
        }

        return ActivityGraph(
            nodes: nodes, edges: edges,
            entryType: entryType, entryMethod: entryMethod
        )
    }

    // MARK: - Node / edge construction

    mutating func makeNode(
        kind: ActivityNodeKind,
        label: String,
        isAsync: Bool = false,
        isUnresolved: Bool = false
    ) -> Int {
        let identifier = nextId
        nextId += 1
        nodes.append(ActivityNode(
            id: identifier, kind: kind, label: label,
            isAsync: isAsync, isUnresolved: isUnresolved
        ))
        return identifier
    }

    mutating func addEdge(from sourceId: Int, to targetId: Int, label: String? = nil) {
        edges.append(ActivityEdge(fromId: sourceId, toId: targetId, label: label))
    }

    // MARK: - Block walking

    mutating func walkBlock(_ items: CodeBlockItemListSyntax) -> WalkResult {
        var firstEntry: Int?
        var currentExits: [Int] = []
        var started = false

        for item in items {
            let result = walkBlockItem(item)
            guard let itemEntry = result.entry else { continue }
            if !started {
                firstEntry = itemEntry
                started = true
            } else {
                for exit in currentExits {
                    addEdge(from: exit, to: itemEntry)
                }
            }
            currentExits = result.exits
        }

        return WalkResult(entry: firstEntry, exits: currentExits)
    }

    mutating func walkBlockItem(_ item: CodeBlockItemSyntax) -> WalkResult {
        switch item.item {
        case .stmt(let stmt):
            return walkStmt(stmt)
        case .expr(let expr):
            return walkExpression(expr)
        case .decl(let decl):
            return walkDecl(decl)
        }
    }

    // MARK: - Statement dispatch

    mutating func walkStmt(_ stmt: StmtSyntax) -> WalkResult {
        if let guardStmt = stmt.as(GuardStmtSyntax.self) {
            return walkGuardStmt(guardStmt)
        }
        if let returnStmt = stmt.as(ReturnStmtSyntax.self) {
            return walkReturnStmt(returnStmt)
        }
        if let throwStmt = stmt.as(ThrowStmtSyntax.self) {
            return walkThrowStmt(throwStmt)
        }
        if let forStmt = stmt.as(ForStmtSyntax.self) {
            return walkForStmt(forStmt)
        }
        if let whileStmt = stmt.as(WhileStmtSyntax.self) {
            return walkWhileStmt(whileStmt)
        }
        if let repeatStmt = stmt.as(RepeatStmtSyntax.self) {
            return walkRepeatStmt(repeatStmt)
        }
        if let doStmt = stmt.as(DoStmtSyntax.self) {
            return walkDoStmt(doStmt)
        }
        if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
            return walkExpression(exprStmt.expression)
        }
        return genericAction(description: stmt.description)
    }

    // MARK: - Expression dispatch

    mutating func walkExpression(_ expr: ExprSyntax) -> WalkResult {
        if let ifExpr = expr.as(IfExprSyntax.self) {
            return walkIfExpr(ifExpr)
        }
        if let switchExpr = expr.as(SwitchExprSyntax.self) {
            return walkSwitchExpr(switchExpr)
        }
        if let awaitExpr = expr.as(AwaitExprSyntax.self) {
            return walkAwaitExpr(awaitExpr)
        }
        if let tryExpr = expr.as(TryExprSyntax.self) {
            return walkExpression(tryExpr.expression)
        }
        if let funcCall = expr.as(FunctionCallExprSyntax.self) {
            if let result = walkTaskGroupCall(funcCall, isAsync: false) {
                return result
            }
            return genericAction(description: expr.description)
        }
        return genericAction(description: expr.description)
    }

    // MARK: - Declarations

    mutating func walkDecl(_ decl: DeclSyntax) -> WalkResult {
        if let variableDecl = decl.as(VariableDeclSyntax.self) {
            if variableDecl.modifiers.contains(where: {
                $0.name.tokenKind == .keyword(.async)
            }) {
                return walkAsyncLet(variableDecl)
            }
            return genericAction(description: variableDecl.description)
        }
        // Nested functions, types, etc. have no flow of their own at this level.
        return WalkResult(entry: nil, exits: [])
    }

    // MARK: - Fallback

    mutating func genericAction(description: String) -> WalkResult {
        let label = Self.compactText(description)
        let identifier = makeNode(kind: .action, label: label)
        return WalkResult(entry: identifier, exits: [identifier])
    }

    // MARK: - Text helpers

    static func compactText(_ text: String) -> String {
        let stripped = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let collapsed = stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > 80 {
            return String(collapsed.prefix(77)) + "…"
        }
        return collapsed
    }

    static func conditionLabel(_ conditions: ConditionElementListSyntax) -> String {
        compactText(conditions.description)
    }

    static func caseLabelText(_ label: SwitchCaseSyntax.Label) -> String {
        switch label {
        case .case(let caseLabel):
            return compactText(caseLabel.caseItems.description)
        case .default:
            return "default"
        }
    }
}
