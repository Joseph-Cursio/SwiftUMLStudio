import Foundation
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
/// * Only stored instance properties are read, as SwiftData stores only those: a `static` or
///   `class` property, or a computed one, is skipped (#140).
/// * A `@Transient` property is never a relationship or a key, whatever its type or its other
///   attributes, since SwiftData stores nothing for it. It is drawn as a transient column (#140).
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
        currentEntityName = node.name.canonicalName
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
        guard !varDecl.modifiers.contains(where: {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }) else { return }
        let relInfo = Self.parseRelationshipAttribute(varDecl.attributes)
        let isUnique = Self.hasUniqueOption(varDecl.attributes)
        let isTransient = Self.hasAttribute(varDecl.attributes, named: "Transient")

        for binding in varDecl.bindings {
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            guard Self.isStored(binding) else { continue }
            let propertyName = identifierPattern.identifier.canonicalName

            let rawType: String
            if let annotation = binding.typeAnnotation {
                rawType = annotation.type.canonicalDescription
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

    /// Whether `binding` has storage: it has no accessors, or only `willSet` / `didSet`. The
    /// `{ … }` getter shorthand, or a list with `get`, `set`, `_read` or `_modify`, is computed.
    /// A closure initializer, `= { 1 }`, is not an accessor block, so it does not count.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        switch binding.accessorBlock?.accessors {
        case nil:
            return true
        case .getter:
            return false
        case .accessors(let accessors):
            return accessors.allSatisfy {
                $0.accessorSpecifier.tokenKind == .keyword(.willSet)
                    || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
            }
        }
    }

    // MARK: - Attribute helpers

    /// Whether the class carries SwiftData's `@Model`, written `@Model` or `@SwiftData.Model`
    /// (#134). Only the class's own attribute is read with its module: SwiftData's `@Model` does
    /// not read a member's `@SwiftData.Attribute`, `@SwiftData.Transient` or
    /// `@SwiftData.Relationship`, so neither does this extractor. A `Model` from any other module
    /// is not SwiftData's.
    static func hasModelAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.names("Model", bareOrIn: "SwiftData")
        }
    }

    static func hasAttribute(
        _ attributes: AttributeListSyntax, named name: String
    ) -> Bool {
        firstAttribute(named: name, in: attributes) != nil
    }

    /// The first attribute named `name`, if any.
    private static func firstAttribute(
        named name: String, in attributes: AttributeListSyntax
    ) -> AttributeSyntax? {
        attributes.lazy.compactMap { $0.as(AttributeSyntax.self) }
            .first { $0.attributeName.canonicalDescription == name }
    }

    /// The arguments an attribute is written with, as `(.unique, originalName: "c")`.
    private static func arguments(of attribute: AttributeSyntax) -> LabeledExprListSyntax {
        guard case .argumentList(let arguments) = attribute.arguments else { return [] }
        return arguments
    }

    /// Whether `@Attribute` lists `.unique` among its options, which are its unlabeled arguments.
    /// They are read from the syntax, not searched for as text, so a comment or a string that
    /// mentions `.unique`, or a labeled argument such as `originalName: Legacy.unique`, does not
    /// count (#128).
    private static func hasUniqueOption(_ attributes: AttributeListSyntax) -> Bool {
        guard let attribute = firstAttribute(named: "Attribute", in: attributes) else { return false }
        return arguments(of: attribute).contains { argument in
            argument.label == nil
                && argument.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.canonicalName == "unique"
        }
    }

    /// Whether the property carries `@Relationship`, and the inverse it names if so.
    private static func parseRelationshipAttribute(
        _ attributes: AttributeListSyntax
    ) -> ERRelationshipAttributeInfo? {
        guard let attribute = firstAttribute(named: "Relationship", in: attributes) else { return nil }
        return ERRelationshipAttributeInfo(inverseProperty: inverseProperty(of: attribute))
    }

    /// The property an `inverse:` key path ends at: `author` for `\Book.author`, also written
    /// `(\Book.author)` or `\Book.author as AnyKeyPath`. It is read from the key path's syntax, so
    /// a comment beside the argument cannot hide or fake one (#128), and the name is read as the
    /// declared label is: `\Book.`author`` names `var author`, and `\Book.`default`` keeps its
    /// backticks, as `var `default`` does (#123). So does `\Book.default`, the same property written
    /// without the backticks a keyword needs only where it is declared (#130).
    private static func inverseProperty(of attribute: AttributeSyntax) -> String? {
        guard let inverse = arguments(of: attribute).first(where: { $0.label?.canonicalName == "inverse" }),
              let keyPath = firstKeyPath(in: Syntax(inverse.expression)) else { return nil }
        for component in keyPath.components.reversed() {
            if case .property(let property) = component.component {
                return property.declName.baseName.memberReferenceName
            }
        }
        return nil
    }

    /// `syntax` if it is a key path, or else the first key path inside it.
    private static func firstKeyPath(in syntax: Syntax) -> KeyPathExprSyntax? {
        if let keyPath = syntax.as(KeyPathExprSyntax.self) { return keyPath }
        return syntax.children(viewMode: .sourceAccurate).lazy.compactMap(firstKeyPath(in:)).first
    }

    /// Best-effort type inference from an initializer expression (e.g.
    /// `= UUID()` → `"UUID"`, `= [] as [Book]` is too rare to matter).
    private static func inferTypeFromInitializer(_ expr: ExprSyntax?) -> String? {
        guard let expr else { return nil }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = callee.baseName.canonicalName
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

                if property.isTransient {
                    attributes.append(Self.attribute(from: property))
                } else if property.isExplicitRelationship {
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
        // Nothing is stored for a @Transient property, so no option or name makes it a key.
        let isUnique = property.isUnique && !property.isTransient
        let isPrimaryKey = !property.isTransient && (isUnique || property.name == "id")
        return ERAttribute(
            name: property.name,
            type: trimmedType,
            isOptional: isOptional,
            isPrimaryKey: isPrimaryKey,
            isUnique: isUnique,
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
    /// discovered in the file, read from `file` when there is one.
    static func extract(from source: String, file: URL? = nil) -> ERModel {
        ParsingStack.run {
            let sourceFile = ParsingStack.parse(source, file: file)
            let extractor = ERModelExtractor(viewMode: .sourceAccurate)
            extractor.walk(sourceFile)
            return extractor.buildModel()
        }
    }
}
