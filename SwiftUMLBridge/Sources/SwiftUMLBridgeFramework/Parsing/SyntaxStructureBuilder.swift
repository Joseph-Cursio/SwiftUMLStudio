import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a parsed Swift source file and builds `SyntaxStructure` instances using
/// SwiftSyntax as the primary source of truth.
///
/// All structural data — type kinds, accessibility, inherited types, generic
/// parameters, and function effect specifiers (async/throws) — is derived from
/// SwiftSyntax nodes directly, and so is a variable's annotation, its own or the one it
/// shares (`a` in `var a, b: Int`). Variable type names for bindings with no annotation
/// are resolved via `typenameMap`, which is pre-populated from a lightweight SourceKit
/// pass in `SyntaxStructureProvider`.
///
/// Every name is read as Swift reads it (`canonicalName`, or `canonicalDescription`
/// for a type), so `` `Plain` `` and `Plain` are one name wherever each is written (#123).
final class SyntaxStructureBuilder: SyntaxVisitor {

    // MARK: - Output

    /// Completed top-level declarations in source order.
    private(set) var topLevelItems: [SyntaxStructure] = []

    // MARK: - Init

    /// The SourceKit typename supplement: the UTF-8 offset of a variable's name → the type
    /// SourceKit gives it.
    private let typenameMap: [Int: String]

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
        typenameMap: [Int: String] = [:],
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
            // `@unchecked Sendable` is `Sendable` (#152) and `(P & Q)` is `P` and `Q` (#160): every
            // reader, from the edges to the excludes, `deps` and `TypeInfo`, takes the plain names.
            for type in inherited.type.conformedTypes {
                let typeName = type.singleLineDescription
                // An entry with no type, as in the unfinished `class Foo: {}`, names nothing.
                if !typeName.isEmpty { result.append(SyntaxStructure(name: typeName)) }
            }
        }
        return result.isEmpty ? nil : result
    }

    private func extractAttributes(from attributes: AttributeListSyntax) -> [SyntaxStructure]? {
        let result = attributes.compactMap { element -> SyntaxStructure? in
            guard case .attribute(let attr) = element else { return nil }
            let name = attr.attributeName.singleLineDescription
            return SyntaxStructure(attribute: name)
        }
        return result.isEmpty ? nil : result
    }

    private func extractGenericParams(from params: GenericParameterListSyntax) -> [SyntaxStructure] {
        params.map { param in
            let constraint = param.inheritedType.map { SyntaxStructure(name: $0.singleLineDescription) }
            return SyntaxStructure(
                inheritedTypes: constraint.map { [$0] },
                kind: .genericTypeParam,
                name: param.name.canonicalName
            )
        }
    }

    func isStaticOrClass(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
    }

    /// The type written for `bindings[index]`: its own annotation, or the one it shares with the
    /// bindings after it, as `a` shares `Int` in `var a, b: Int`. A binding with no annotation and
    /// no initializer has the type of the next one with an annotation; Swift rejects the
    /// declaration if a binding between them has an initializer or accessors. Reading this from
    /// the syntax gives `a` its type when the SourceKit supplement is off, as in the App Store
    /// build (#146).
    private static func annotatedType(of index: Int, in bindings: [PatternBindingSyntax]) -> String? {
        for binding in bindings[index...] {
            if let annotation = binding.typeAnnotation { return annotation.type.singleLineDescription }
            if binding.initializer != nil || binding.accessorBlock != nil { return nil }
        }
        return nil
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
            name: node.name.canonicalName
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
            // `Foo<Int>` is `Foo` constrained (SE-0361): named as `extension Foo where T == Int` is (#66).
            name: node.extendedType.extendedTypeName ?? node.extendedType.canonicalDescription
        )
        if node.extendedType.extendedTypeName != nil {
            structure.boundGenericArguments = node.extendedType.boundGenericArguments
        }
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

        let bindings = Array(node.bindings)
        for (index, binding) in bindings.enumerated() {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.canonicalName else {
                continue
            }
            let typename = Self.annotatedType(of: index, in: bindings)
                ?? typenameMap[binding.pattern.positionAfterSkippingLeadingTrivia.utf8Offset]
            appendMember(SyntaxStructure(accessibility: accessibility, kind: kind, name: name, typename: typename))
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !typeStack.isEmpty else { return .skipChildren }
        appendMember(SyntaxStructure(
            accessibility: extractAccessibility(from: node.modifiers),
            kind: isStaticOrClass(node.modifiers) ? .functionMethodStatic : .functionMethodInstance,
            name: node.name.canonicalName,
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
        let elements = node.elements.map { SyntaxStructure(kind: .enumelement, name: $0.name.canonicalName) }
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
