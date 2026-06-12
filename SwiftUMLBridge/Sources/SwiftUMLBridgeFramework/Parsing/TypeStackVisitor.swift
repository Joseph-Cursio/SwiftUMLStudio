import SwiftSyntax

/// A `SyntaxVisitor` that maintains a stack of the enclosing type names while it
/// walks class / struct / enum / actor / protocol / extension declarations.
///
/// Subclasses read `typeStack.last` to learn the type that currently encloses the
/// node being visited. A subclass that needs to do extra work for one of these
/// declarations (e.g. collecting enum cases) overrides the matching `visit(_:)`,
/// performs its work, and returns `super.visit(node)` so the stack stays balanced.
class TypeStackVisitor: SyntaxVisitor {
    /// Enclosing type names, outermost first; `last` is the innermost type.
    private(set) var typeStack: [String] = []

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

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.description.trimmingCharacters(in: .whitespacesAndNewlines))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }
}
