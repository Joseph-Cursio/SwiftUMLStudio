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

    /// File path used when stamping each declaration's `sourceLocation`. May be
    /// empty when parsing from an in-memory string.
    private let filePath: String

    /// SwiftSyntax line/column converter for the parsed source file. `nil` when
    /// no converter was provided (in which case `sourceLocation` is left unset).
    private let locationConverter: SourceLocationConverter?

    /// SPM target / module the file belongs to. Stamped onto each top-level
    /// declaration so downstream layers can render module-qualified diagrams.
    private let module: String?

    init(
        viewMode: SyntaxTreeViewMode = .sourceAccurate,
        typenameMap: [String: String] = [:],
        filePath: String = "",
        locationConverter: SourceLocationConverter? = nil,
        module: String? = nil
    ) {
        self.typenameMap = typenameMap
        self.filePath = filePath
        self.locationConverter = locationConverter
        self.module = module
        super.init(viewMode: viewMode)
    }

    /// Capture the 1-based line/column of `node`'s identifier and stamp it onto
    /// `structure.sourceLocation` (and `module` from this builder's context).
    /// `sourceLocation` is left nil if no `locationConverter` was supplied;
    /// `module` is left nil if no module was supplied.
    private func stampLocation(on structure: SyntaxStructure, at position: AbsolutePosition) {
        if let converter = locationConverter {
            let resolved = converter.location(for: position)
            structure.sourceLocation = SwiftUMLBridgeFramework.SourceLocation(
                filePath: filePath,
                line: resolved.line,
                column: resolved.column
            )
        }
        structure.module = module
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

    /// Shared handling for the named, member-bearing type declarations
    /// (class / struct / enum / actor / protocol): build the `SyntaxStructure`,
    /// stamp its source location, and push it onto the type stack.
    private func handleTypeDeclaration(
        _ node: some NamedDeclSyntax & DeclGroupSyntax,
        kind: ElementKind,
        genericParameterClause: GenericParameterClauseSyntax?
    ) -> SyntaxVisitorContinueKind {
        let genericParams = extractGenericParams(from: genericParameterClause?.parameters ?? [])
        let structure = SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: kind,
            name: node.name.text
        )
        stampLocation(on: structure, at: node.name.positionAfterSkippingLeadingTrivia)
        pushType(structure, genericParams: genericParams)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDeclaration(node, kind: .class, genericParameterClause: node.genericParameterClause)
    }
    override func visitPost(_ node: ClassDeclSyntax) { _ = node; popType() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDeclaration(node, kind: .struct, genericParameterClause: node.genericParameterClause)
    }
    override func visitPost(_ node: StructDeclSyntax) { _ = node; popType() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDeclaration(node, kind: .enum, genericParameterClause: node.genericParameterClause)
    }
    override func visitPost(_ node: EnumDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDeclaration(node, kind: .actor, genericParameterClause: node.genericParameterClause)
    }
    override func visitPost(_ node: ActorDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        handleTypeDeclaration(node, kind: .protocol, genericParameterClause: nil)
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { _ = node; popType() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let structure = SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            inheritedTypes: extractInheritedTypes(from: node.inheritanceClause),
            kind: .extension,
            name: node.extendedType.trimmedDescription
        )
        stampLocation(on: structure, at: node.extendedType.positionAfterSkippingLeadingTrivia)
        pushType(structure)
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
