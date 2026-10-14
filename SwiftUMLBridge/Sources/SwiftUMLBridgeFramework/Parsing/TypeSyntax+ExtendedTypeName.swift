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
        case .tupleType(let tuple):
            // `(T)` is `T` itself; a real tuple cannot be extended.
            guard tuple.elements.count == 1, let only = tuple.elements.first, only.firstName == nil,
                  only.secondName == nil, only.ellipsis == nil else { return nil }
            return only.type.extendedTypeName
        default: return nil
        }
    }
}
