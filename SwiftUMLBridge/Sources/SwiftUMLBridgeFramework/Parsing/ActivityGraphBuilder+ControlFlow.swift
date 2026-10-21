import Foundation
import SwiftSyntax

/// Control-flow walkers for `ActivityGraphBuilder`: if/guard/switch, `#if`, loops,
/// return/throw, and do/catch.
extension ActivityGraphBuilder {

    // MARK: - Branch wiring

    /// Wire a freshly-walked branch `result` into the graph: connect `decisionId`
    /// to the block's entry under `label` (or straight to `mergeId` when the block
    /// is empty), then route every block exit to `mergeId`.
    private mutating func wireBranch(
        _ result: WalkResult,
        from decisionId: Int,
        to mergeId: Int,
        label: String
    ) {
        if let entry = result.entry {
            addEdge(from: decisionId, to: entry, label: label)
        } else {
            addEdge(from: decisionId, to: mergeId, label: label)
        }
        for exit in result.exits {
            addEdge(from: exit, to: mergeId)
        }
    }

    // MARK: - If / guard

    mutating func walkIfExpr(_ node: IfExprSyntax) -> WalkResult {
        let label = Self.conditionLabel(node.conditions)
        let decisionId = makeNode(kind: .decision, label: label)
        let mergeId = makeNode(kind: .merge, label: "")

        wireBranch(walkBlock(node.body.statements), from: decisionId, to: mergeId, label: "true")

        if let elseBody = node.elseBody {
            wireElseBody(elseBody, decisionId: decisionId, mergeId: mergeId)
        } else {
            addEdge(from: decisionId, to: mergeId, label: "false")
        }

        return WalkResult(entry: decisionId, exits: [mergeId])
    }

    private mutating func wireElseBody(
        _ elseBody: IfExprSyntax.ElseBody,
        decisionId: Int,
        mergeId: Int
    ) {
        switch elseBody {
        case .ifExpr(let elseIf):
            wireBranch(walkIfExpr(elseIf), from: decisionId, to: mergeId, label: "false")
        case .codeBlock(let elseBlock):
            wireBranch(walkBlock(elseBlock.statements), from: decisionId, to: mergeId, label: "false")
        }
    }

    mutating func walkGuardStmt(_ node: GuardStmtSyntax) -> WalkResult {
        let label = Self.conditionLabel(node.conditions)
        let decisionId = makeNode(kind: .decision, label: label)

        wireBranch(walkBlock(node.body.statements), from: decisionId, to: endNodeId, label: "false")

        return WalkResult(entry: decisionId, exits: [decisionId])
    }

    // MARK: - Switch

    mutating func walkSwitchExpr(_ node: SwitchExprSyntax) -> WalkResult {
        let subject = Self.compactText(node.subject.trimmedDescription)
        let decisionId = makeNode(kind: .decision, label: "switch \(subject)")
        let mergeId = makeNode(kind: .merge, label: "")

        for switchCase in Self.casesInEveryClause(node.cases) {
            let branchLabel = Self.caseLabelText(switchCase.label)
            wireBranch(walkBlock(switchCase.statements), from: decisionId, to: mergeId, label: branchLabel)
        }

        return WalkResult(entry: decisionId, exits: [mergeId])
    }

    /// Each case of a switch in source order, with an `#if` among the cases replaced by the cases
    /// of all its clauses. A case inside `#if` is a branch like any other, as the call graph and
    /// the state-machine reader read it (#135).
    static func casesInEveryClause(_ cases: SwitchCaseListSyntax) -> [SwitchCaseSyntax] {
        cases.flatMap { element -> [SwitchCaseSyntax] in
            switch element {
            case .switchCase(let switchCase):
                return [switchCase]
            case .ifConfigDecl(let ifConfig):
                return ifConfig.clauses.flatMap { clause -> [SwitchCaseSyntax] in
                    guard case .switchCases(let nested)? = clause.elements else { return [] }
                    return casesInEveryClause(nested)
                }
            }
        }
    }

    // MARK: - #if

    /// An `#if` among statements is a decision with one branch per clause, labelled as the clause
    /// is written: `#if DEBUG`, `#elseif os(iOS)`, `#else`. Without an `#else`, an empty `#else`
    /// branch goes straight to the merge, as an `if` without `else` does. The conditions are not
    /// evaluated, since neither the CLI nor Studio knows which hold, so every clause is drawn.
    mutating func walkIfConfig(_ node: IfConfigDeclSyntax) -> WalkResult {
        let decisionId = makeNode(kind: .decision, label: "#if")
        let mergeId = makeNode(kind: .merge, label: "")

        for clause in node.clauses {
            let keyword = clause.poundKeyword.text
            let branchLabel = clause.condition
                .map { "\(keyword) \(Self.compactText($0.trimmedDescription))" } ?? keyword
            let result: WalkResult
            if case .statements(let statements)? = clause.elements {
                result = walkBlock(statements)
            } else {
                result = WalkResult(entry: nil, exits: [])
            }
            wireBranch(result, from: decisionId, to: mergeId, label: branchLabel)
        }
        if !node.clauses.contains(where: { $0.poundKeyword.tokenKind == .poundElse }) {
            addEdge(from: decisionId, to: mergeId, label: "#else")
        }

        return WalkResult(entry: decisionId, exits: [mergeId])
    }

    // MARK: - Loops

    mutating func walkForStmt(_ node: ForStmtSyntax) -> WalkResult {
        let pattern = Self.compactText(node.pattern.trimmedDescription)
        let sequence = Self.compactText(node.sequence.trimmedDescription)
        let loopId = makeNode(kind: .loopStart, label: "for \(pattern) in \(sequence)")

        let bodyResult = walkBlock(node.body.statements)
        if let entry = bodyResult.entry {
            addEdge(from: loopId, to: entry, label: "iterate")
        }
        for exit in bodyResult.exits {
            addEdge(from: exit, to: loopId)
        }

        return WalkResult(entry: loopId, exits: [loopId])
    }

    mutating func walkWhileStmt(_ node: WhileStmtSyntax) -> WalkResult {
        let condition = Self.conditionLabel(node.conditions)
        let loopId = makeNode(kind: .loopStart, label: "while \(condition)")

        let bodyResult = walkBlock(node.body.statements)
        if let entry = bodyResult.entry {
            addEdge(from: loopId, to: entry, label: "true")
        }
        for exit in bodyResult.exits {
            addEdge(from: exit, to: loopId)
        }

        return WalkResult(entry: loopId, exits: [loopId])
    }

    mutating func walkRepeatStmt(_ node: RepeatStmtSyntax) -> WalkResult {
        let condition = Self.compactText(node.condition.trimmedDescription)
        let loopId = makeNode(kind: .loopStart, label: "while \(condition)")

        let bodyResult = walkBlock(node.body.statements)
        guard let entry = bodyResult.entry else {
            return WalkResult(entry: loopId, exits: [loopId])
        }
        for exit in bodyResult.exits {
            addEdge(from: exit, to: loopId)
        }
        addEdge(from: loopId, to: entry, label: "true")
        return WalkResult(entry: entry, exits: [loopId])
    }

    // MARK: - Return / throw

    mutating func walkReturnStmt(_ node: ReturnStmtSyntax) -> WalkResult {
        let label: String
        if let expression = node.expression {
            label = "return \(Self.compactText(expression.trimmedDescription))"
        } else {
            label = "return"
        }
        let identifier = makeNode(kind: .action, label: label)
        addEdge(from: identifier, to: endNodeId)
        return WalkResult(entry: identifier, exits: [])
    }

    mutating func walkThrowStmt(_ node: ThrowStmtSyntax) -> WalkResult {
        let label = "throw \(Self.compactText(node.expression.trimmedDescription))"
        let identifier = makeNode(kind: .action, label: label)
        addEdge(from: identifier, to: endNodeId)
        return WalkResult(entry: identifier, exits: [])
    }

    // MARK: - Do / catch

    mutating func walkDoStmt(_ node: DoStmtSyntax) -> WalkResult {
        if node.catchClauses.isEmpty {
            return walkBlock(node.body.statements)
        }

        let decisionId = makeNode(kind: .decision, label: "try")
        let mergeId = makeNode(kind: .merge, label: "")

        wireBranch(walkBlock(node.body.statements), from: decisionId, to: mergeId, label: "success")

        for catchClause in node.catchClauses {
            wireCatchClause(catchClause, decisionId: decisionId, mergeId: mergeId)
        }

        return WalkResult(entry: decisionId, exits: [mergeId])
    }

    private mutating func wireCatchClause(
        _ catchClause: CatchClauseSyntax,
        decisionId: Int,
        mergeId: Int
    ) {
        let catchItemText = catchClause.catchItems.trimmedDescription
        let branchLabel = catchItemText.isEmpty
            ? "catch"
            : "catch \(Self.compactText(catchItemText))"
        wireBranch(walkBlock(catchClause.body.statements), from: decisionId, to: mergeId, label: branchLabel)
    }
}
