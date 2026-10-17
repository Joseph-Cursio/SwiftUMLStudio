import SwiftSyntax

/// A `SyntaxVisitor` that maintains a stack of the enclosing type names while it
/// walks class / struct / enum / actor / protocol / extension declarations.
///
/// Each type is named as Swift reads it, so `` struct `Plain` `` pushes `Plain`, the name a
/// call to it or an extension of it is filed under (#123).
///
/// Subclasses read `typeStack.last` to learn the type that currently encloses the
/// node being visited. A subclass that needs to do extra work for one of these
/// declarations (e.g. collecting enum cases) overrides the matching `visit(_:)`,
/// performs its work, and returns `super.visit(node)` so the stack stays balanced.
class TypeStackVisitor: SyntaxVisitor {
    /// Enclosing type names, outermost first; `last` is the innermost type.
    private(set) var typeStack: [String] = []

    /// The type a name written in this file means, for the names an extension and a call's
    /// receiver are written with: `TypeAliasResolver.resolve(_:in:)` follows typealiases (#125).
    /// The name itself by default.
    var resolveTypeName: (String) -> String = { $0 }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.canonicalName)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.canonicalName)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.canonicalName)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.canonicalName)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.canonicalName)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Named as `SyntaxStructureBuilder` names the extension, so a sequence participant finds
        // its source location under it, and `Foo<Int>` and `[Int]` read `Foo` and `Array` (#66).
        // `extension Alias` is the aliased type's (#125).
        typeStack.append(resolveTypeName(node.extendedType.extendedTypeName ?? node.extendedType.canonicalDescription))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }
}
