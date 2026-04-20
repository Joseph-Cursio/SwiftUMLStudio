import Foundation
import SwiftSyntax

/// Concurrency walkers for `ActivityGraphBuilder`:
/// - `await`-wrapped actions
/// - `async let` bindings → fork/join with one branch per binding
/// - `withTaskGroup` / `withThrowingTaskGroup` / `withDiscardingTaskGroup` /
///   `withThrowingDiscardingTaskGroup` + `group.addTask { … }` → fork/join
///   with one branch per task closure.
extension ActivityGraphBuilder {

    // MARK: - Await

    mutating func walkAwaitExpr(_ node: AwaitExprSyntax) -> WalkResult {
        if let funcCall = node.expression.as(FunctionCallExprSyntax.self) {
            if let result = walkTaskGroupCall(funcCall, isAsync: true) {
                return result
            }
        }
        let label = Self.compactText(node.description)
        let identifier = makeNode(kind: .action, label: label, isAsync: true)
        return WalkResult(entry: identifier, exits: [identifier])
    }

    // MARK: - Async let

    mutating func walkAsyncLet(_ node: VariableDeclSyntax) -> WalkResult {
        let forkId = makeNode(kind: .fork, label: "")
        let joinId = makeNode(kind: .join, label: "")
        for binding in node.bindings {
            let pattern = Self.compactText(binding.pattern.description)
            let actionId = makeNode(
                kind: .action,
                label: "async let \(pattern)",
                isAsync: true
            )
            addEdge(from: forkId, to: actionId)
            addEdge(from: actionId, to: joinId)
        }
        return WalkResult(entry: forkId, exits: [joinId])
    }

    // MARK: - Task groups

    mutating func walkTaskGroupCall(
        _ node: FunctionCallExprSyntax,
        isAsync: Bool
    ) -> WalkResult? {
        guard Self.isTaskGroupName(node.calledExpression) else { return nil }
        guard let closure = Self.trailingOrLastClosure(of: node) else { return nil }

        // Collect the task closures up front so we only emit fork/join when there's at least one branch.
        let taskClosures: [ClosureExprSyntax] = closure.statements.compactMap { item in
            guard let addTaskCall = Self.extractAddTaskCall(from: item) else { return nil }
            return Self.trailingOrLastClosure(of: addTaskCall)
        }

        if taskClosures.isEmpty {
            let callName = Self.calledName(node) ?? "taskGroup"
            let identifier = makeNode(
                kind: .action,
                label: "\(callName) { … }",
                isAsync: isAsync
            )
            return WalkResult(entry: identifier, exits: [identifier])
        }

        let forkId = makeNode(kind: .fork, label: "")
        let joinId = makeNode(kind: .join, label: "")

        for taskClosure in taskClosures {
            let taskResult = walkBlock(taskClosure.statements)
            if let entry = taskResult.entry {
                addEdge(from: forkId, to: entry)
            } else {
                addEdge(from: forkId, to: joinId)
            }
            for exit in taskResult.exits {
                addEdge(from: exit, to: joinId)
            }
        }

        return WalkResult(entry: forkId, exits: [joinId])
    }

    // MARK: - Static helpers

    static func isTaskGroupName(_ expr: ExprSyntax) -> Bool {
        guard let ref = expr.as(DeclReferenceExprSyntax.self) else { return false }
        return taskGroupCallNames.contains(ref.baseName.text)
    }

    static func calledName(_ node: FunctionCallExprSyntax) -> String? {
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    static func trailingOrLastClosure(of node: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        if let trailing = node.trailingClosure {
            return trailing
        }
        for argument in node.arguments.reversed() {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                return closure
            }
        }
        return nil
    }

    static func extractAddTaskCall(from item: CodeBlockItemSyntax) -> FunctionCallExprSyntax? {
        guard case .expr(let expr) = item.item else { return nil }
        if let call = expr.as(FunctionCallExprSyntax.self), isAddTaskCall(call.calledExpression) {
            return call
        }
        if let awaitExpr = expr.as(AwaitExprSyntax.self),
           let call = awaitExpr.expression.as(FunctionCallExprSyntax.self),
           isAddTaskCall(call.calledExpression) {
            return call
        }
        if let tryExpr = expr.as(TryExprSyntax.self),
           let call = tryExpr.expression.as(FunctionCallExprSyntax.self),
           isAddTaskCall(call.calledExpression) {
            return call
        }
        return nil
    }

    static func isAddTaskCall(_ expr: ExprSyntax) -> Bool {
        guard let member = expr.as(MemberAccessExprSyntax.self) else { return false }
        return addTaskCallNames.contains(member.declName.baseName.text)
    }
}

// MARK: - Private constants

private let taskGroupCallNames: Set<String> = [
    "withTaskGroup", "withThrowingTaskGroup",
    "withDiscardingTaskGroup", "withThrowingDiscardingTaskGroup"
]

private let addTaskCallNames: Set<String> = [
    "addTask", "addTaskUnlessCancelled"
]
