import SwiftParser
import SwiftSyntax

extension TypeSyntax {
    /// The name an extension of this type is drawn under: the extended type's own name, or its
    /// dotted path, with every generic argument and all sugar removed. `Foo<Int>` → `Foo`,
    /// `Outer<Int>.Inner<String>` → `Outer.Inner`, `[Int]` → `Array`, `[String: Int]` →
    /// `Dictionary`, `[3 of Int]` → `InlineArray`, `Int?` → `Optional`, `(Foo<Int>)` → `Foo`. Each
    /// name is its `canonicalName`: `` `Foo` `` → `Foo`, while `` `Foo Bar` `` keeps its backticks.
    ///
    /// So `extension Foo<Int>` is named exactly as `extension Foo where T == Int` is, the
    /// constraint it is shorthand for (SE-0361). `nil` for a type no extension can extend (a
    /// tuple, function, composition, existential or metatype) and for a parse error: the
    /// compiler rejects all of those.
    var extendedTypeName: String? {
        switch self.as(TypeSyntaxEnum.self) {
        case .identifierType(let identifier):
            return identifier.name.presence == .present ? identifier.name.canonicalName : nil
        case .memberType(let member):
            guard member.name.presence == .present, let base = member.baseType.extendedTypeName else { return nil }
            return base + "." + member.name.canonicalName
        case .arrayType: return "Array"
        case .dictionaryType: return "Dictionary"
        case .inlineArrayType: return "InlineArray"
        case .optionalType, .implicitlyUnwrappedOptionalType: return "Optional"
        case .tupleType(let tuple): return tuple.parenthesizedType?.extendedTypeName
        default: return nil
        }
    }

    /// The generic arguments this type binds on the type `extendedTypeName` names, as written but
    /// with each name canonical, joined with `", "`, for display beside that name: `Foo<Int>` →
    /// `Int`, `Outer<Int>.Inner<String>` → `String` (only the last component's), `[Int]` and
    /// `Int?` → `Int`, `[String: Int]` → `String, Int`, `[3 of Int]` → `3, Int`. `nil` when it
    /// binds none.
    var boundGenericArguments: String? {
        switch self.as(TypeSyntaxEnum.self) {
        case .identifierType(let identifier): return identifier.genericArgumentClause?.argumentText
        case .memberType(let member): return member.genericArgumentClause?.argumentText
        case .arrayType(let array): return [array.element].argumentText
        case .dictionaryType(let dictionary): return [dictionary.key, dictionary.value].argumentText
        case .inlineArrayType(let inline): return [inline.count.argument, inline.element.argument].argumentText
        case .optionalType(let optional): return [optional.wrappedType].argumentText
        case .implicitlyUnwrappedOptionalType(let unwrapped): return [unwrapped.wrappedType].argumentText
        case .tupleType(let tuple): return tuple.parenthesizedType?.boundGenericArguments
        default: return nil
        }
    }

    /// The type an inheritance-clause entry conforms to, without the attributes and specifiers
    /// that say how: `P` for `@MainActor P`, `@preconcurrency P`, `@retroactive P`, `@unsafe P` or
    /// `nonisolated P`, `Sendable` for `@unchecked Sendable`, `P & Q` for `@MainActor P & Q`, whose
    /// attribute covers the whole composition, and `(P)` for `@MainActor (P)`. Every other type is
    /// itself; `~Copyable` is a suppressed conformance, not an attributed one, and stays as written.
    var conformedType: TypeSyntax {
        var type = self
        while let attributed = type.as(AttributedTypeSyntax.self) {
            if let reread = attributed.typeAfterArgumentlessAttribute { return reread.conformedType }
            type = attributed.baseType
        }
        return type
    }
}

private extension AttributedTypeSyntax {
    /// In Swift 6, `@MainActor (P)` is `@MainActor` applied to the type `(P)`: the space before
    /// `(` ends the attribute. swift-syntax reads `(P)` as the attribute's arguments instead, and
    /// leaves the type missing. This is the type read again from that `(` on, as the compiler reads
    /// it: `(P)`, `(P & Q)`, `(P) & Q`. `nil` when the type is there.
    var typeAfterArgumentlessAttribute: TypeSyntax? {
        guard baseType.hasError, case .attribute(let attribute)? = attributes.last,
              let leftParen = attribute.leftParen,
              !attribute.attributeName.trailingTrivia.isEmpty || !leftParen.leadingTrivia.isEmpty
        else { return nil }
        var parser = Parser(
            leftParen.trimmedDescription + (attribute.arguments?.description ?? "")
                + (attribute.rightParen?.description ?? "") + baseType.description
        )
        return TypeSyntax.parse(from: &parser)
    }
}

extension ExprSyntax {
    /// The name `extendedTypeName` gives the type this expression writes, when it writes one as a
    /// call receiver can: `Foo<Int>` → `Foo`, `Outer<Int>.Inner<String>` → `Outer.Inner`,
    /// `Swift.Array<Int>` → `Swift.Array`, `[Int]` → `Array`, `[String: Int]` → `Dictionary`,
    /// `Int?` → `Optional`. So `Foo<Int>.make()` calls into the name an extension of `Foo<Int>` is
    /// listed under (#66), and `` `Foo`.make() `` into `Foo` (#123). `nil` for anything else, a
    /// lowercase name included: that is a value.
    var typeReferenceName: String? {
        switch self.as(ExprSyntaxEnum.self) {
        case .declReferenceExpr(let reference):
            let name = reference.baseName.expressionName
            return name.first?.isUppercase == true ? name : nil
        case .memberAccessExpr(let member):
            let name = member.declName.baseName.canonicalName
            guard name.first?.isUppercase == true, let base = member.base?.typeReferenceName else { return nil }
            return base + "." + name
        case .genericSpecializationExpr(let specialized):
            return specialized.expression.typeReferenceName
        case .typeExpr(let type):
            return type.type.extendedTypeName
        case .optionalChainingExpr(let optional):
            return optional.expression.typeReferenceName == nil ? nil : "Optional"
        case .arrayExpr(let array):
            guard array.elements.count == 1, array.elements.first?.expression.typeReferenceName != nil else {
                return nil
            }
            return "Array"
        case .dictionaryExpr(let dictionary):
            guard case .elements(let elements) = dictionary.content, elements.count == 1, let only = elements.first,
                  only.key.typeReferenceName != nil, only.value.typeReferenceName != nil else { return nil }
            return "Dictionary"
        default:
            return nil
        }
    }
}

private extension TupleTypeSyntax {
    /// The type inside `(T)`, which is `T` itself; `nil` for a real tuple, which no extension
    /// can extend.
    var parenthesizedType: TypeSyntax? {
        guard elements.count == 1, let only = elements.first, only.firstName == nil,
              only.secondName == nil, only.ellipsis == nil else { return nil }
        return only.type
    }
}

private extension GenericArgumentClauseSyntax {
    var argumentText: String? { arguments.map(\.argument).argumentText }
}

private extension Sequence where Element: SyntaxProtocol {
    /// The elements' canonical text joined with `", "`, or `nil` when there is none.
    var argumentText: String? {
        let parts = map(\.singleLineDescription).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
