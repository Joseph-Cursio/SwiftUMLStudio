import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and extracts candidate state machines.
///
/// Heuristic (M1): an enum used as a state property on a host type (class/struct/actor)
/// where transitions happen via `self.prop = .case` assignments inside `switch self.prop`
/// branches. Enums with associated values on any case are rejected.
final class StateMachineExtractor: SyntaxVisitor {

    // MARK: - Collected data

    /// Map of enum type name → ordered list of case names.
    /// Only present when every case has no associated values.
    private var simpleEnums: [String: [String]] = [:]

    /// Per host type: property name → declared type annotation.
    private var typeProperties: [String: [String: String]] = [:]

    /// Records raw transitions observed during the walk.
    private var observedTransitions: [ObservedTransition] = []

    // MARK: - Walk state

    private var typeStack: [String] = []
    private var funcStack: [String] = []
    private var switchStack: [SwitchFrame] = []

    private struct SwitchFrame {
        let subjectPropertyName: String?
        var currentCaseName: String?
    }

    private struct ObservedTransition {
        let typeName: String
        let funcName: String
        let propertyName: String
        let rhsCaseName: String
        let switchCaseName: String?
        let switchSubjectMatches: Bool
    }

    // MARK: - Type declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.extendedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        typeStack.append(typeName)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let enumName = node.name.text
        var caseNames: [String] = []
        var rejected = false

        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                if element.parameterClause != nil {
                    rejected = true
                    break
                }
                caseNames.append(element.name.text)
            }
            if rejected { break }
        }

        if !rejected && !caseNames.isEmpty {
            simpleEnums[enumName] = caseNames
        }

        typeStack.append(enumName)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

    // MARK: - Property declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last else { return .visitChildren }
        // Only top-level properties inside a type body (not locals within function bodies)
        guard funcStack.isEmpty else { return .visitChildren }

        for binding in node.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let annotation = binding.typeAnnotation else { continue }
            let propertyName = identifierPattern.identifier.text
            let annotationText = annotation.type.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            typeProperties[typeName, default: [:]][propertyName] = annotationText
        }
        return .visitChildren
    }

    // MARK: - Function declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        funcStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: FunctionDeclSyntax) { funcStack.removeLast() }

    // MARK: - Switch tracking

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        switchStack.append(SwitchFrame(
            subjectPropertyName: Self.propertyName(from: node.subject),
            currentCaseName: nil
        ))
        return .visitChildren
    }
    override func visitPost(_ node: SwitchExprSyntax) { switchStack.removeLast() }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        guard !switchStack.isEmpty else { return .visitChildren }
        let caseName = Self.extractEnumCaseLabel(from: node)
        switchStack[switchStack.count - 1].currentCaseName = caseName
        return .visitChildren
    }

    // MARK: - Assignment detection

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last, let funcName = funcStack.last else {
            return .visitChildren
        }
        let elements = Array(node.elements)
        guard elements.count >= 3 else { return .visitChildren }

        for index in 1..<(elements.count - 1) {
            guard elements[index].is(AssignmentExprSyntax.self) else { continue }
            let lhs = elements[index - 1]
            let rhs = elements[index + 1]
            guard let propertyName = Self.propertyName(from: ExprSyntax(lhs)),
                  let rhsCase = Self.enumCaseFromMemberAccess(ExprSyntax(rhs)) else { continue }

            let activeSwitch = switchStack.last(where: { $0.currentCaseName != nil })
            let matches = activeSwitch?.subjectPropertyName == propertyName
            observedTransitions.append(ObservedTransition(
                typeName: typeName,
                funcName: funcName,
                propertyName: propertyName,
                rhsCaseName: rhsCase,
                switchCaseName: activeSwitch?.currentCaseName,
                switchSubjectMatches: matches
            ))
        }
        return .visitChildren
    }

    // MARK: - Shape helpers

    /// Extract the property name from expressions of the form `self.prop` or `prop`.
    private static func propertyName(from expr: ExprSyntax) -> String? {
        if let memberAccess = expr.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base,
           base.description.trimmingCharacters(in: .whitespacesAndNewlines) == "self" {
            return memberAccess.declName.baseName.text
        }
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        return nil
    }

    /// Extract `case` from a `.case` member-access expression with no base (enum shorthand).
    private static func enumCaseFromMemberAccess(_ expr: ExprSyntax) -> String? {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self),
              memberAccess.base == nil else { return nil }
        return memberAccess.declName.baseName.text
    }

    /// Extract the enum case label from a `case .foo:` switch case.
    private static func extractEnumCaseLabel(from node: SwitchCaseSyntax) -> String? {
        guard case .case(let label) = node.label else { return nil }
        for item in label.caseItems {
            if let pattern = item.pattern.as(ExpressionPatternSyntax.self),
               let memberAccess = pattern.expression.as(MemberAccessExprSyntax.self),
               memberAccess.base == nil {
                return memberAccess.declName.baseName.text
            }
        }
        return nil
    }

    // MARK: - Post-processing

    /// Resolve observed data into `StateMachineModel` candidates.
    private func buildCandidates() -> [StateMachineModel] {
        var result: [StateMachineModel] = []

        let bucketed = Dictionary(grouping: observedTransitions) { obs in
            "\(obs.typeName)|\(obs.propertyName)"
        }

        for (_, group) in bucketed {
            guard let first = group.first else { continue }
            guard let enumType = typeProperties[first.typeName]?[first.propertyName] else { continue }
            guard let cases = simpleEnums[enumType] else { continue }

            let transitions: [StateTransition] = group.compactMap { obs in
                guard obs.switchSubjectMatches, let from = obs.switchCaseName else { return nil }
                return StateTransition(from: from, toState: obs.rhsCaseName, trigger: obs.funcName)
            }
            guard !transitions.isEmpty else { continue }

            let finalNames: Set<String> = ["done", "finished", "completed", "terminated", "error"]
            let destinations = Set(transitions.map(\.toState))
            let sources = Set(transitions.map(\.from))
            let states: [StateMachineState] = cases.enumerated().map { index, caseName in
                let isInitial = index == 0
                let isFinal = finalNames.contains(caseName.lowercased())
                    && !sources.contains(caseName)
                    && destinations.contains(caseName)
                return StateMachineState(
                    name: caseName,
                    isInitial: isInitial,
                    isFinal: isFinal
                )
            }

            result.append(StateMachineModel(
                hostType: first.typeName,
                enumType: enumType,
                states: states,
                transitions: transitions
            ))
        }

        return result.sorted { $0.identifier < $1.identifier }
    }

    // MARK: - Static factory

    /// Parse `source` and extract all candidate state machines.
    static func extract(from source: String) -> [StateMachineModel] {
        let sourceFile = Parser.parse(source: source)
        let extractor = StateMachineExtractor(viewMode: .sourceAccurate)
        extractor.walk(sourceFile)
        return extractor.buildCandidates()
    }
}
