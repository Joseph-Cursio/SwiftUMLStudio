import SwiftSyntax

extension FunctionDeclSyntax {
    /// Whether this is a member of the type around it: written directly in a member block, under
    /// an `#if` too. A function local to a method, initializer, accessor, subscript or closure is
    /// not, though the type's name is still on the stack: `T.method` cannot name it.
    var isMember: Bool {
        parent?.is(MemberBlockItemSyntax.self) == true
    }
}

extension SyntaxProtocol {
    /// Whether a function, initializer, accessor or closure holds this, or a statement in
    /// top-level code does. A function local to one is no member, and a type local to one can be
    /// named only inside it, so choosing among several types for an entry counts neither.
    var isInsideBody: Bool {
        sequence(first: Syntax(self), next: \.parent).dropFirst().contains {
            $0.is(CodeBlockSyntax.self) || $0.is(ClosureExprSyntax.self)
                || $0.is(AccessorBlockSyntax.self) || $0.is(SwitchCaseSyntax.self)
        }
    }

    /// The type or extension declaration nearest around this.
    var enclosingTypeDeclaration: Syntax? {
        sequence(first: Syntax(self), next: \.parent).dropFirst().first { $0.isProtocol(DeclGroupSyntax.self) }
    }

    /// The function named `name` that a body around this declares, nearest first, as Swift looks
    /// up a bare call: before a member of that name, and wherever in the body it is written. The
    /// search ends at the members of the type around this, as a member is not looked for here.
    func localFunction(named name: String) -> FunctionDeclSyntax? {
        for ancestor in sequence(first: Syntax(self), next: \.parent).dropFirst() {
            if ancestor.is(MemberBlockSyntax.self) { return nil }
            guard let statements = ancestor.as(CodeBlockItemListSyntax.self) else { continue }
            for statement in statements {
                if let function = statement.item.as(FunctionDeclSyntax.self), function.name.canonicalName == name {
                    return function
                }
            }
        }
        return nil
    }

    /// The type named `name` that a body around this declares, nearest first, which a name
    /// written here means before any type declared outside a body.
    func localType(named name: String) -> Syntax? {
        for ancestor in sequence(first: Syntax(self), next: \.parent).dropFirst() {
            guard let statements = ancestor.as(CodeBlockItemListSyntax.self),
                  !(statements.parent?.is(SourceFileSyntax.self) ?? true) else { continue }
            for statement in statements {
                let item = statement.item
                let declared = item.as(StructDeclSyntax.self)?.name ?? item.as(ClassDeclSyntax.self)?.name
                    ?? item.as(EnumDeclSyntax.self)?.name ?? item.as(ActorDeclSyntax.self)?.name
                if declared?.canonicalName == name { return Syntax(item) }
            }
        }
        return nil
    }
}

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
