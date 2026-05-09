import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and extracts an `ERModel` from
/// non-SwiftData persistence stacks. v1 covers GRDB; SQLite.swift detection
/// will follow in milestone G2 of er-diagram-expansion-plan.md.
///
/// GRDB heuristic: a class/struct/actor declared to conform to one of
/// `FetchableRecord` / `PersistableRecord` / `MutablePersistableRecord` /
/// `EncodableRecord` / `TableRecord` is treated as an entity. Stored
/// (non-static, non-computed) properties become attributes; `static let`
/// declarations whose initializer is `belongsTo(X.self)` / `hasMany(X.self)`
/// / `hasOne(X.self)` become relationships with the documented cardinality.
public enum PersistenceSchemaExtractor {

    /// Recognised GRDB record protocol names (any of these on a type triggers
    /// detection — we don't require all of them).
    static let grdbRecordProtocols: Set<String> = [
        "FetchableRecord",
        "PersistableRecord",
        "MutablePersistableRecord",
        "EncodableRecord",
        "TableRecord"
    ]

    static let grdbAssociationFunctions: Set<String> = [
        "belongsTo", "hasMany", "hasOne", "hasManyThrough"
    ]

    public static func extract(from source: String) -> ERModel {
        let sourceFile = Parser.parse(source: source)
        let visitor = Visitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        return ERModel(entities: visitor.entities, relationships: visitor.relationships)
    }

    // MARK: - SyntaxVisitor

    final class Visitor: SyntaxVisitor {
        private(set) var entities: [EREntity] = []
        private(set) var relationships: [ERRelationship] = []

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            handleType(name: node.name.text,
                       inheritance: node.inheritanceClause,
                       members: node.memberBlock.members)
            return .skipChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            handleType(name: node.name.text,
                       inheritance: node.inheritanceClause,
                       members: node.memberBlock.members)
            return .skipChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            handleType(name: node.name.text,
                       inheritance: node.inheritanceClause,
                       members: node.memberBlock.members)
            return .skipChildren
        }

        private func handleType(
            name: String,
            inheritance: InheritanceClauseSyntax?,
            members: MemberBlockItemListSyntax
        ) {
            guard let inheritance, conformsToGRDBRecord(inheritance) else { return }

            var attributes: [ERAttribute] = []
            for case let member as MemberBlockItemSyntax in members {
                guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

                if let relationship = grdbRelationship(from: varDecl, ownerType: name) {
                    relationships.append(relationship)
                    continue
                }

                if isStatic(varDecl.modifiers) { continue }

                attributes.append(contentsOf: columns(from: varDecl))
            }
            entities.append(EREntity(name: name, attributes: attributes))
        }

        // MARK: - Inheritance check

        private func conformsToGRDBRecord(_ clause: InheritanceClauseSyntax) -> Bool {
            for inherited in clause.inheritedTypes {
                let raw = inherited.type.trimmedDescription
                // Strip generics + protocol composition (`A & B`)
                let parts = raw
                    .components(separatedBy: "&")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for part in parts {
                    let bare = part.split(separator: "<").first.map(String.init) ?? part
                    if PersistenceSchemaExtractor.grdbRecordProtocols.contains(bare) {
                        return true
                    }
                }
            }
            return false
        }

        // MARK: - Columns

        private func columns(from varDecl: VariableDeclSyntax) -> [ERAttribute] {
            var result: [ERAttribute] = []
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    continue
                }
                let raw = binding.typeAnnotation?.type.trimmedDescription ?? "Any"
                let isOptional = raw.hasSuffix("?")
                let trimmed = isOptional ? String(raw.dropLast()) : raw
                let isPrimaryKey = name == "id"
                result.append(ERAttribute(
                    name: name,
                    type: trimmed,
                    isOptional: isOptional,
                    isPrimaryKey: isPrimaryKey
                ))
            }
            return result
        }

        private func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
            modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        }

        // MARK: - Relationships

        /// Detect `static let team = belongsTo(Team.self)` style declarations.
        private func grdbRelationship(from varDecl: VariableDeclSyntax, ownerType: String) -> ERRelationship? {
            guard isStatic(varDecl.modifiers) else { return nil }
            guard let binding = varDecl.bindings.first,
                  let label = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self)
            else { return nil }

            guard let funcName = associationFunctionName(in: initializer),
                  PersistenceSchemaExtractor.grdbAssociationFunctions.contains(funcName)
            else { return nil }

            guard let target = firstTypeArgument(in: initializer.arguments) else { return nil }

            let (fromCardinality, toCardinality) = cardinality(for: funcName)
            return ERRelationship(
                from: ownerType,
                toEntity: target,
                fromCardinality: fromCardinality,
                toCardinality: toCardinality,
                label: label
            )
        }

        private func associationFunctionName(in call: FunctionCallExprSyntax) -> String? {
            if let identifier = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return identifier.baseName.text
            }
            if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
                return memberAccess.declName.baseName.text
            }
            return nil
        }

        private func firstTypeArgument(in arguments: LabeledExprListSyntax) -> String? {
            guard let firstArg = arguments.first,
                  let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "self",
                  let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self)
            else { return nil }
            return baseRef.baseName.text
        }

        private func cardinality(for functionName: String) -> (from: ERCardinality, to: ERCardinality) {
            switch functionName {
            case "belongsTo":
                return (.zeroOrMany, .exactlyOne)
            case "hasMany", "hasManyThrough":
                return (.exactlyOne, .zeroOrMany)
            case "hasOne":
                return (.exactlyOne, .zeroOrOne)
            default:
                return (.zeroOrMany, .zeroOrMany)
            }
        }
    }
}
