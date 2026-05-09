import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and extracts an `ERModel` from
/// non-SwiftData persistence stacks. Covers two patterns:
///
/// - **GRDB**: a class/struct/actor declared to conform to one of
///   `FetchableRecord` / `PersistableRecord` / `MutablePersistableRecord` /
///   `EncodableRecord` / `TableRecord`. Stored (non-static, non-computed)
///   properties become attributes; `static let` declarations whose
///   initializer is `belongsTo(X.self)` / `hasMany(X.self)` / `hasOne(X.self)`
///   become relationships.
/// - **SQLite.swift**: a "schema container" type (struct / enum / class) that
///   declares one or more `static let X = Table("name")` properties. Each
///   `Table("name")` becomes an entity; `static let X = Expression<T>("col")`
///   declarations in the same container become its columns when the container
///   has exactly one table (otherwise columns are emitted as un-owned tables).
///   SQLite.swift has no built-in association API, so no relationships are
///   inferred.
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

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            // SQLite.swift schema containers are typically enums-as-namespaces.
            // GRDB never uses enums for record types, so we only check the
            // SQLite.swift path here.
            extractSQLiteSwiftTables(name: node.name.text, members: node.memberBlock.members)
            return .skipChildren
        }

        private func handleType(
            name: String,
            inheritance: InheritanceClauseSyntax?,
            members: MemberBlockItemListSyntax
        ) {
            if let inheritance, conformsToGRDBRecord(inheritance) {
                handleGRDBType(name: name, members: members)
                return
            }
            extractSQLiteSwiftTables(name: name, members: members)
        }

        private func handleGRDBType(name: String, members: MemberBlockItemListSyntax) {
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

        // MARK: - SQLite.swift

        /// Walks a "schema container" type for `static let X = Table("name")`
        /// and `static let X = Expression<T>("col")` declarations. Each Table
        /// becomes an entity; Expression columns are attached to the single
        /// Table sibling when the container has exactly one (the common
        /// case). When the container has multiple Tables we emit them all
        /// without columns to avoid mis-attributing.
        private func extractSQLiteSwiftTables(name _: String, members: MemberBlockItemListSyntax) {
            var tableNames: [String] = []
            var columnAttributes: [ERAttribute] = []

            for case let member as MemberBlockItemSyntax in members {
                guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                      isStatic(varDecl.modifiers),
                      let binding = varDecl.bindings.first,
                      let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      let funcName = associationFunctionName(in: initializer)
                else { continue }

                if funcName == "Table" {
                    if let tableName = firstStringLiteral(in: initializer.arguments) {
                        tableNames.append(tableName)
                    }
                    continue
                }

                if funcName == "Expression",
                   let columnName = firstStringLiteral(in: initializer.arguments) {
                    let typeName = expressionGenericType(of: initializer) ?? "Any"
                    columnAttributes.append(ERAttribute(
                        name: columnName,
                        type: typeName,
                        isPrimaryKey: columnName == "id"
                    ))
                }
            }

            guard !tableNames.isEmpty else { return }
            if tableNames.count == 1 {
                entities.append(EREntity(name: tableNames[0], attributes: columnAttributes))
            } else {
                for tableName in tableNames {
                    entities.append(EREntity(name: tableName))
                }
            }
        }

        /// Pull the first string literal out of a function-call argument list.
        /// Used for `Table("users")` and `Expression<Int64>("id")`.
        private func firstStringLiteral(in arguments: LabeledExprListSyntax) -> String? {
            guard let firstArg = arguments.first,
                  let stringExpr = firstArg.expression.as(StringLiteralExprSyntax.self)
            else { return nil }
            return stringExpr.segments
                .compactMap { ($0.as(StringSegmentSyntax.self))?.content.text }
                .joined()
        }

        /// Extract `Int64` from an `Expression<Int64>(...)` call by inspecting
        /// the generic argument list on the called expression.
        private func expressionGenericType(of call: FunctionCallExprSyntax) -> String? {
            if let generic = call.calledExpression.as(GenericSpecializationExprSyntax.self) {
                return generic.genericArgumentClause.arguments.first?.argument.trimmedDescription
            }
            return nil
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
            // Generic specialization, e.g. `Expression<Int64>("id")`. The
            // .expression slot holds the bare DeclReference under the type
            // arguments — unwrap to get the function name.
            if let generic = call.calledExpression.as(GenericSpecializationExprSyntax.self),
               let baseRef = generic.expression.as(DeclReferenceExprSyntax.self) {
                return baseRef.baseName.text
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
