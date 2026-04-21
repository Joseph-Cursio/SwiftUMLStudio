import Foundation
import SwiftParser
import SwiftSyntax

/// Raw property shape captured during the first SwiftSyntax pass over a
/// `@Model` class. We can't classify a property as "attribute" vs
/// "relationship" until we know every `@Model` class name in the file, so
/// we hold the raw info and defer classification to `buildModel()`.
private struct ERCandidateProperty {
    let name: String
    let rawType: String
    let isExplicitRelationship: Bool
    let inverseProperty: String?
    let isUnique: Bool
    let isTransient: Bool
}

/// Sentinel for the presence of a `@Relationship` attribute, along with the
/// inverse property name if it was declared.
private struct ERRelationshipAttributeInfo {
    let inverseProperty: String?
}

/// Walks a parsed Swift source file and extracts an `ERModel` built from
/// SwiftData `@Model` classes.
///
/// Heuristic (M1, single-file):
/// * An entity is any `class` carrying an `@Model` attribute.
/// * A property becomes a relationship if either (a) it carries an explicit
///   `@Relationship` attribute or (b) its (unwrapped) type name matches
///   another `@Model` class seen in the same file.
/// * Relationship cardinality is inferred from the declarer's property type:
///   `[T]` / `Set<T>` → zero-or-many, `T?` → zero-or-one, `T` → exactly-one.
///   The *other* endpoint's cardinality is defaulted (one-per-many for to-one
///   properties, exactly-one for to-many) and resolved against real inverses
///   in a follow-up commit.
/// * When two properties declare the same edge from opposite sides (e.g.,
///   `Author.books` with an explicit inverse and `Book.author` without one),
///   the explicit side wins and the implicit side is dropped.
final class ERModelExtractor: SyntaxVisitor {

    // MARK: - Collected data

    private var entities: [(name: String, properties: [ERCandidateProperty])] = []

    // MARK: - Walk state

    private var currentEntityProperties: [ERCandidateProperty] = []
    private var currentEntityName: String?

    // MARK: - Type declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard Self.hasModelAttribute(node.attributes) else { return .skipChildren }
        currentEntityName = node.name.text
        currentEntityProperties = []
        for member in node.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                collectProperty(from: varDecl)
            }
        }
        if let name = currentEntityName {
            entities.append((name: name, properties: currentEntityProperties))
        }
        currentEntityName = nil
        currentEntityProperties = []
        return .skipChildren
    }

    // MARK: - Property collection

    private func collectProperty(from varDecl: VariableDeclSyntax) {
        let relInfo = Self.parseRelationshipAttribute(varDecl.attributes)
        let isUnique = Self.hasAttribute(varDecl.attributes, named: "Attribute")
            && Self.attributeArgumentText(varDecl.attributes, named: "Attribute")
                .contains(".unique")
        let isTransient = Self.hasAttribute(varDecl.attributes, named: "Transient")

        for binding in varDecl.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            let propertyName = identifierPattern.identifier.text

            let rawType: String
            if let annotation = binding.typeAnnotation {
                rawType = annotation.type.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let inferred = Self.inferTypeFromInitializer(binding.initializer?.value) {
                rawType = inferred
            } else {
                continue
            }

            currentEntityProperties.append(ERCandidateProperty(
                name: propertyName,
                rawType: rawType,
                isExplicitRelationship: relInfo != nil,
                inverseProperty: relInfo?.inverseProperty,
                isUnique: isUnique,
                isTransient: isTransient
            ))
        }
    }

    // MARK: - Attribute helpers

    private static func hasModelAttribute(_ attributes: AttributeListSyntax) -> Bool {
        hasAttribute(attributes, named: "Model")
    }

    private static func hasAttribute(
        _ attributes: AttributeListSyntax, named name: String
    ) -> Bool {
        for attribute in attributes {
            guard let attribute = attribute.as(AttributeSyntax.self) else { continue }
            if attribute.attributeName.description
                .trimmingCharacters(in: .whitespacesAndNewlines) == name {
                return true
            }
        }
        return false
    }

    /// Returns the concatenated argument text of the first attribute matching
    /// `name`, or an empty string if none found. Used for substring sniffing
    /// (e.g., detecting `.unique` inside `@Attribute(.unique)`).
    private static func attributeArgumentText(
        _ attributes: AttributeListSyntax, named name: String
    ) -> String {
        for attribute in attributes {
            guard let attribute = attribute.as(AttributeSyntax.self) else { continue }
            guard attribute.attributeName.description
                .trimmingCharacters(in: .whitespacesAndNewlines) == name else { continue }
            return attribute.arguments?.description ?? ""
        }
        return ""
    }

    /// Parse the arguments of `@Relationship(...)` and pull out the inverse
    /// property name, if specified as a KeyPath like `\Book.author`.
    private static func parseRelationshipAttribute(
        _ attributes: AttributeListSyntax
    ) -> ERRelationshipAttributeInfo? {
        for attribute in attributes {
            guard let attribute = attribute.as(AttributeSyntax.self) else { continue }
            guard attribute.attributeName.description
                .trimmingCharacters(in: .whitespacesAndNewlines) == "Relationship" else { continue }
            let argText = attribute.arguments?.description ?? ""
            return ERRelationshipAttributeInfo(
                inverseProperty: extractInverseProperty(from: argText)
            )
        }
        return nil
    }

    /// Pull the trailing property name out of `inverse: \Book.author` → "author".
    private static func extractInverseProperty(from argText: String) -> String? {
        guard let range = argText.range(of: "inverse:") else { return nil }
        let afterInverse = argText[range.upperBound...]
        guard let backslash = afterInverse.firstIndex(of: "\\") else { return nil }
        let afterBackslash = afterInverse[afterInverse.index(after: backslash)...]
        guard let dot = afterBackslash.firstIndex(of: ".") else { return nil }
        let propertyStart = afterBackslash.index(after: dot)
        let remainder = afterBackslash[propertyStart...]
        let terminators: Set<Character> = [",", ")", " ", "\n", "\t"]
        let endIndex = remainder.firstIndex(where: { terminators.contains($0) }) ?? remainder.endIndex
        let name = String(remainder[..<endIndex])
        return name.isEmpty ? nil : name
    }

    /// Best-effort type inference from an initializer expression (e.g.
    /// `= UUID()` → `"UUID"`, `= [] as [Book]` is too rare to matter).
    private static func inferTypeFromInitializer(_ expr: ExprSyntax?) -> String? {
        guard let expr else { return nil }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = callee.baseName.text
            if name.first?.isUppercase == true { return name }
        }
        return nil
    }

    // MARK: - Post-walk construction

    /// Resolve the collected raw data into an `ERModel`.
    fileprivate func buildModel() -> ERModel {
        let modelNames = Set(entities.map(\.name))

        var eroEntities: [EREntity] = []
        var explicit: [ERRelationship] = []
        var implicit: [ERRelationship] = []

        for (entityName, properties) in entities {
            var attributes: [ERAttribute] = []
            for property in properties {
                let (targetType, cardinality) = Self.unwrapRelationshipType(property.rawType)

                if property.isExplicitRelationship {
                    explicit.append(Self.relationship(
                        from: entityName, toEntity: targetType,
                        toCardinality: cardinality, property: property
                    ))
                } else if modelNames.contains(targetType) {
                    implicit.append(Self.relationship(
                        from: entityName, toEntity: targetType,
                        toCardinality: cardinality, property: property
                    ))
                } else {
                    attributes.append(Self.attribute(from: property))
                }
            }
            eroEntities.append(EREntity(name: entityName, attributes: attributes))
        }

        let deduped = Self.dedupe(explicit: explicit, implicit: implicit)
        return ERModel(entities: eroEntities, relationships: deduped)
    }

    private static func attribute(from property: ERCandidateProperty) -> ERAttribute {
        let isOptional = property.rawType.hasSuffix("?")
        let trimmedType = isOptional
            ? String(property.rawType.dropLast())
            : property.rawType
        let isPrimaryKey = property.isUnique || property.name == "id"
        return ERAttribute(
            name: property.name,
            type: trimmedType,
            isOptional: isOptional,
            isPrimaryKey: isPrimaryKey,
            isUnique: property.isUnique,
            isTransient: property.isTransient
        )
    }

    private static func relationship(
        from: String,
        toEntity: String,
        toCardinality: ERCardinality,
        property: ERCandidateProperty
    ) -> ERRelationship {
        let fromCardinality: ERCardinality
        switch toCardinality {
        case .zeroOrMany, .oneOrMany:
            fromCardinality = .exactlyOne
        case .zeroOrOne, .exactlyOne:
            fromCardinality = .zeroOrMany
        }
        return ERRelationship(
            from: from,
            toEntity: toEntity,
            fromCardinality: fromCardinality,
            toCardinality: toCardinality,
            label: property.name,
            inverseLabel: property.inverseProperty
        )
    }

    /// Unwrap a property's raw type string into (targetTypeName, cardinality).
    ///
    /// Recognizes `[T]`, `Array<T>`, `Set<T>` as to-many; `T?` / `Optional<T>`
    /// as optional to-one; bare `T` as required to-one. Generics deeper than
    /// one level (`[[T]]`, `Set<Array<T>>`) collapse to the innermost element
    /// with to-many cardinality.
    static func unwrapRelationshipType(_ raw: String) -> (String, ERCardinality) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (innerType, _) = unwrapRelationshipType(inner)
            return (innerType, .zeroOrMany)
        }
        if trimmed.hasPrefix("Array<"), trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst("Array<".count).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (innerType, _) = unwrapRelationshipType(inner)
            return (innerType, .zeroOrMany)
        }
        if trimmed.hasPrefix("Set<"), trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst("Set<".count).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (innerType, _) = unwrapRelationshipType(inner)
            return (innerType, .zeroOrMany)
        }
        if trimmed.hasPrefix("Optional<"), trimmed.hasSuffix(">") {
            let inner = String(trimmed.dropFirst("Optional<".count).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (innerType, _) = unwrapRelationshipType(inner)
            return (innerType, .zeroOrOne)
        }
        if trimmed.hasSuffix("?") {
            let inner = String(trimmed.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (inner, .zeroOrOne)
        }
        return (trimmed, .exactlyOne)
    }

    /// Drop implicit relationships whose reverse direction is already covered
    /// by an explicit `@Relationship` declaration.
    private static func dedupe(
        explicit: [ERRelationship],
        implicit: [ERRelationship]
    ) -> [ERRelationship] {
        var result = explicit
        for candidate in implicit {
            let covered = explicit.contains { explicit in
                explicit.from == candidate.toEntity
                    && explicit.toEntity == candidate.from
                    && (explicit.inverseLabel == candidate.label
                        || explicit.label == candidate.inverseLabel)
            }
            if !covered {
                result.append(candidate)
            }
        }
        return result
    }

    // MARK: - Static factory

    /// Parse `source` and extract an `ERModel` containing every `@Model` class
    /// discovered in the file.
    static func extract(from source: String) -> ERModel {
        let sourceFile = Parser.parse(source: source)
        let extractor = ERModelExtractor(viewMode: .sourceAccurate)
        extractor.walk(sourceFile)
        return extractor.buildModel()
    }
}
