import SwiftSyntax

extension TypeSyntax {
    /// The name an extension of this type is drawn under: the extended type's own name, or its
    /// dotted path, with every generic argument and all sugar removed. `Foo<Int>` → `Foo`,
    /// `Outer<Int>.Inner<String>` → `Outer.Inner`, `[Int]` → `Array`, `[String: Int]` →
    /// `Dictionary`, `[3 of Int]` → `InlineArray`, `Int?` → `Optional`, `(Foo<Int>)` → `Foo`.
    ///
    /// So `extension Foo<Int>` is named exactly as `extension Foo where T == Int` is, the
    /// constraint it is shorthand for (SE-0361). `nil` for a type no extension can extend (a
    /// tuple, function, composition, existential or metatype) and for a parse error: the
    /// compiler rejects all of those.
    var extendedTypeName: String? {
        switch self.as(TypeSyntaxEnum.self) {
        case .identifierType(let identifier):
            return identifier.name.presence == .present ? identifier.name.text : nil
        case .memberType(let member):
            guard member.name.presence == .present, let base = member.baseType.extendedTypeName else { return nil }
            return base + "." + member.name.text
        case .arrayType: return "Array"
        case .dictionaryType: return "Dictionary"
        case .inlineArrayType: return "InlineArray"
        case .optionalType, .implicitlyUnwrappedOptionalType: return "Optional"
        case .tupleType(let tuple): return tuple.parenthesizedType?.extendedTypeName
        default: return nil
        }
    }

    /// The generic arguments this type binds on the type `extendedTypeName` names, as written
    /// and joined with `", "`, for display beside that name: `Foo<Int>` → `Int`,
    /// `Outer<Int>.Inner<String>` → `String` (only the last component's), `[Int]` and `Int?` →
    /// `Int`, `[String: Int]` → `String, Int`, `[3 of Int]` → `3, Int`. `nil` when it binds none.
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
    /// The elements' text joined with `", "`, or `nil` when there is none.
    var argumentText: String? {
        let parts = map(\.trimmedDescription).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
