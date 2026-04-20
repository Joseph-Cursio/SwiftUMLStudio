import Foundation
import SwiftSyntax

/// Control-flow walkers for `ActivityGraphBuilder`: if/guard/switch, loops,
/// return/throw, and do/catch.
extension ActivityGraphBuilder {

    // MARK: - If / guard

    mutating func walkIfExpr(_ node: IfExprSyntax) -> WalkResult {
        let label = Self.conditionLabel(node.conditions)
        let decisionId = makeNode(kind: .decision, label: label)
        let mergeId = makeNode(kind: .merge, label: "")

        let thenResult = walkBlock(node.body.statements)
        if let entry = thenResult.entry {
            addEdge(from: decisionId, to: entry, label: "true")
        } else {
            addEdge(from: decisionId, to: mergeId, label: "true")
        }
        for exit in thenResult.exits {
            addEdge(from: exit, to: mergeId)
        }

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
            let nested = walkIfExpr(elseIf)
            if let entry = nested.entry {
                addEdge(from: decisionId, to: entry, label: "false")
            } else {
                addEdge(from: decisionId, to: mergeId, label: "false")
            }
            for exit in nested.exits {
                addEdge(from: exit, to: mergeId)
            }
        case .codeBlock(let elseBlock):
            let elseResult = walkBlock(elseBlock.statements)
            if let entry = elseResult.entry {
                addEdge(from: decisionId, to: entry, label: "false")
            } else {
                addEdge(from: decisionId, to: mergeId, label: "false")
            }
            for exit in elseResult.exits {
                addEdge(from: exit, to: mergeId)
            }
        }
    }

    mutating func walkGuardStmt(_ node: GuardStmtSyntax) -> WalkResult {
        let label = Self.conditionLabel(node.conditions)
        let decisionId = makeNode(kind: .decision, label: label)

        let elseResult = walkBlock(node.body.statements)
        if let entry = elseResult.entry {
            addEdge(from: decisionId, to: entry, label: "false")
        } else {
            addEdge(from: decisionId, to: endNodeId, label: "false")
        }
        for exit in elseResult.exits {
            addEdge(from: exit, to: endNodeId)
        }

        return WalkResult(entry: decisionId, exits: [decisionId])
    }

    // MARK: - Switch

    mutating func walkSwitchExpr(_ node: SwitchExprSyntax) -> WalkResult {
        let subject = Self.compactText(node.subject.description)
        let decisionId = makeNode(kind: .decision, label: "switch \(subject)")
        let mergeId = makeNode(kind: .merge, label: "")

        for caseElement in node.cases {
            guard let switchCase = caseElement.as(SwitchCaseSyntax.self) else { continue }
            let branchLabel = Self.caseLabelText(switchCase.label)
            let result = walkBlock(switchCase.statements)
            if let entry = result.entry {
                addEdge(from: decisionId, to: entry, label: branchLabel)
            } else {
                addEdge(from: decisionId, to: mergeId, label: branchLabel)
            }
            for exit in result.exits {
                addEdge(from: exit, to: mergeId)
            }
        }

        return WalkResult(entry: decisionId, exits: [mergeId])
    }

    // MARK: - Loops

    mutating func walkForStmt(_ node: ForStmtSyntax) -> WalkResult {
        let pattern = Self.compactText(node.pattern.description)
        let sequence = Self.compactText(node.sequence.description)
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
        let condition = Self.compactText(node.condition.description)
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
            label = "return \(Self.compactText(expression.description))"
        } else {
            label = "return"
        }
        let identifier = makeNode(kind: .action, label: label)
        addEdge(from: identifier, to: endNodeId)
        return WalkResult(entry: identifier, exits: [])
    }

    mutating func walkThrowStmt(_ node: ThrowStmtSyntax) -> WalkResult {
        let label = "throw \(Self.compactText(node.expression.description))"
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

        let bodyResult = walkBlock(node.body.statements)
        if let entry = bodyResult.entry {
            addEdge(from: decisionId, to: entry, label: "success")
        } else {
            addEdge(from: decisionId, to: mergeId, label: "success")
        }
        for exit in bodyResult.exits {
            addEdge(from: exit, to: mergeId)
        }

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
        let catchItemText = catchClause.catchItems.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let branchLabel = catchItemText.isEmpty
            ? "catch"
            : "catch \(Self.compactText(catchItemText))"
        let result = walkBlock(catchClause.body.statements)
        if let entry = result.entry {
            addEdge(from: decisionId, to: entry, label: branchLabel)
        } else {
            addEdge(from: decisionId, to: mergeId, label: branchLabel)
        }
        for exit in result.exits {
            addEdge(from: exit, to: mergeId)
        }
    }
}
