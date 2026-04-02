import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and builds `SyntaxStructure` instances using
/// SwiftSyntax as the primary source of truth.
///
/// All structural data — type kinds, accessibility, inherited types, generic
/// parameters, and function effect specifiers (async/throws) — is derived from
/// SwiftSyntax nodes directly. Variable type names for bindings with no explicit
/// annotation are resolved via `typenameMap`, which is pre-populated from a
/// lightweight SourceKit pass in `SyntaxStructureProvider`.
final class SyntaxStructureBuilder: SyntaxVisitor {

    // MARK: - Output

    /// Completed top-level declarations in source order.
    private(set) var topLevelItems: [SyntaxStructure] = []

    // MARK: - Init

    /// `qualifiedVarName → resolvedTypeName` from the SourceKit typename supplement.
    private let typenameMap: [String: String]

    init(viewMode: SyntaxTreeViewMode = .sourceAccurate, typenameMap: [String: String] = [:]) {
        self.typenameMap = typenameMap
        super.init(viewMode: viewMode)
    }

    // MARK: - Type stack

    private var typeStack: [(structure: SyntaxStructure, children: [SyntaxStructure])] = []

    private func pushType(_ structure: SyntaxStructure, genericParams: [SyntaxStructure] = []) {
        typeStack.append((structure: structure, children: genericParams))
    }

    private func popType() {
        guard let frame = typeStack.popLast() else { return }
        frame.structure.substructure = frame.children.isEmpty ? nil : frame.children
        if typeStack.isEmpty {
            topLevelItems.append(frame.structure)
        } else {
            typeStack[typeStack.count - 1].children.append(frame.structure)
        }
    }

    private func appendMember(_ member: SyntaxStructure) {
        guard !typeStack.isEmpty else { return }
        typeStack[typeStack.count - 1].children.append(member)
    }

    /// Qualified name for a variable within the current type stack context.
    private func qualifiedVarName(_ varName: String) -> String {
        let typeNames = typeStack.compactMap(\.structure.name)
        return (typeNames + [varName]).joined(separator: ".")
    }

    // MARK: - Extraction helpers

    private func extractAccessibility(from modifiers: DeclModifierListSyntax) -> ElementAccessibility {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.open): return .open
            case .keyword(.public): return .public
            case .keyword(.package): return .package
            case .keyword(.internal): return .internal
            case .keyword(.private): return .private
            case .keyword(.fileprivate): return .fileprivate
            default: continue
            }
        }
        return .internal
    }

    private func extractInheritedTypes(from clause: InheritanceClauseSyntax?) -> [SyntaxStructure]? {
        guard let clause else { return nil }
        var result: [SyntaxStructure] = []
        for inherited in clause.inheritedTypes {
            let typeName = inherited.type.trimmedDescription
            if typeName.contains("&") {
                // Compound type (A & B) — split into individual entries
                let parts = typeName.components(separatedBy: "&")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                result.append(contentsOf: parts.map { SyntaxStructure(name: $0) })
            } else {
                result.append(SyntaxStructure(name: typeName))
            }
        }
        return result.isEmpty ? nil : result
    }

    private func extractAttributes(from attributes: AttributeListSyntax) -> [SyntaxStructure]? {
        let result = attributes.compactMap { element -> SyntaxStructure? in
            guard case .attribute(let attr) = element else { return nil }
            let name = attr.attributeName.trimmedDescription
            return SyntaxStructure(attribute: name)
        }
        return result.isEmpty ? nil : result
    }

    private func extractGenericParams(from params: GenericParameterListSyntax) -> [SyntaxStructure] {
        params.map { param in
            let constraint = param.inheritedType.map { SyntaxStructure(name: $0.trimmedDescription) }
            return SyntaxStructure(
                inheritedTypes: constraint.map { [$0] },
                kind: .genericTypeParam,
                name: param.name.text
            )
        }
    }

    private func isStaticOrClass(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
    }

    private func effectSpecifierTypename(for specifiers: FunctionEffectSpecifiersSyntax?) -> String? {
        let isAsync = specifiers?.asyncSpecifier != nil
        let isThrows = specifiers?.throwsClause != nil
        if isAsync && isThrows { return "async throws" }
        if isAsync { return "async" }
        if isThrows { return "throws" }
        return nil
    }

    // MARK: - Type declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let genericParams = extractGenericParams(from: node.genericParameterClause?.parameters ?? [])
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .class,
            name: node.name.text
        ), genericParams: genericParams)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { _ = node; popType() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let genericParams = extractGenericParams(from: node.genericParameterClause?.parameters ?? [])
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .struct,
            name: node.name.text
        ), genericParams: genericParams)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { _ = node; popType() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let genericParams = extractGenericParams(from: node.genericParameterClause?.parameters ?? [])
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .enum,
            name: node.name.text
        ), genericParams: genericParams)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let genericParams = extractGenericParams(from: node.genericParameterClause?.parameters ?? [])
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .actor,
            name: node.name.text
        ), genericParams: genericParams)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .protocol,
            name: node.name.text
        ))
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .extension,
            name: node.extendedType.trimmedDescription
        ))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { _ = node; popType() }

    // MARK: - Member declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        let isStatic = isStaticOrClass(node.modifiers)
        let accessibility = extractAccessibility(from: node.modifiers)
        let kind: ElementKind = isStatic ? .varStatic : .varInstance

        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                continue
            }
            let explicitTypename = binding.typeAnnotation?.type.trimmedDescription
            let typename = explicitTypename ?? typenameMap[qualifiedVarName(name)]
            appendMember(SyntaxStructure(accessibility: accessibility, kind: kind, name: name, typename: typename))
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        appendMember(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            kind: isStaticOrClass(node.modifiers) ? .functionMethodStatic : .functionMethodInstance,
            name: node.name.text,
            typename: effectSpecifierTypename(for: node.signature.effectSpecifiers)
        ))
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        appendMember(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            kind: .functionConstructor,
            name: "init"
        ))
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        appendMember(SyntaxStructure(kind: .functionDestructor, name: "deinit"))
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        let elements = node.elements.map { SyntaxStructure(kind: .enumelement, name: $0.name.text) }
        appendMember(SyntaxStructure(kind: .enumcase, substructure: elements.isEmpty ? nil : elements))
        return .skipChildren
    }

    // Prevent traversal into subscript / accessor bodies
    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = node; return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = node; return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        _ = node; return .skipChildren
    }
}
