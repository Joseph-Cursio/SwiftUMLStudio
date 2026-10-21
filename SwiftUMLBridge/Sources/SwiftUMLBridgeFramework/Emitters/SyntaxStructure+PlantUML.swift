import Foundation

extension SyntaxStructure {
    /// Textual representation of this element in PlantUML scripting language
    func plantuml(context: DiagramContext) -> String? {
        renderDiagramText(context: context) { kind, generics, context in
            plantUMLText(for: kind, generics: generics, context: context)
        }
    }

    // Maps an ElementKind to its PlantUML textual representation.
    //
    // This is the only emitter that reads `configuration.stereotypes`, and that
    // is by design rather than an oversight in the other two: a `Stereotype` is
    // a spot — one character and a colour, rendered `<< (C, DarkSeaGreen) >>` —
    // which is PlantUML syntax with no counterpart in Mermaid's `<<label>>` or
    // nomnoml's `<label>`. `docs/user/reference.md` documents custom spot
    // stereotypes as a PlantUML-specific feature.
    private func plantUMLText(
        for kind: ElementKind,
        generics: String?,
        context: DiagramContext
    ) -> String? {
        let stereotypes = context.configuration.stereotypes
        switch kind {
        case ElementKind.class:
            return plantUMLClassNode(
                relationship: "inherits",
                stereotype: stereotypes.class?.plantuml ?? Stereotype.class.plantuml,
                generics: generics, context: context
            )
        case ElementKind.struct:
            return plantUMLClassNode(
                relationship: "inherits",
                stereotype: stereotypes.struct?.plantuml ?? Stereotype.struct.plantuml,
                generics: generics, context: context
            )
        case ElementKind.extension:
            return plantUMLClassNode(
                relationship: "ext",
                stereotype: stereotypes.extension?.plantuml ?? Stereotype.extension.plantuml,
                generics: generics, context: context
            )
        case ElementKind.enum:
            return plantUMLClassNode(
                relationship: "",
                stereotype: stereotypes.enum?.plantuml ?? Stereotype.enum.plantuml,
                generics: generics, context: context
            )
        case ElementKind.protocol:
            return plantUMLClassNode(
                relationship: "conforms to",
                stereotype: stereotypes.protocol?.plantuml ?? Stereotype.protocol.plantuml,
                generics: generics, context: context
            )
        case ElementKind.actor:
            return plantUMLClassNode(
                relationship: "actor",
                stereotype: Stereotype.actor.plantuml,
                generics: generics, context: context
            )
        case ElementKind.macro:
            let macroName = context.uniqName(item: self, relationship: "macro")
            return "note as \(macroName)\n  <<macro>> \(displayName ?? "unknown")\nend note"
        default:
            BridgeLogger.shared.error("element kind not supported for PlantUML rendering: \(kind.rawValue)")
            return nil
        }
    }

    /// Build a PlantUML class-node declaration line for this element.
    private func plantUMLClassNode(
        relationship: String,
        stereotype: String,
        generics: String?,
        context: DiagramContext
    ) -> String {
        let alias = context.uniqName(item: self, relationship: relationship)
        // PlantUML's generic part ends at the first `>`, so the one in a function type's `->`
        // (`extension [() -> Void]`) would leave the rest of the header unreadable.
        let genericsStr = generics?.replacingOccurrences(of: "->", with: "→") ?? ""
        let body = members(context: context)
        let macroAnnotation = attributeNames.map { " <<\($0)>>" }.joined()
        let moduleAnnotation = module.map { " <<\($0)>>" } ?? ""
        let typeName = displayName ?? name ?? "unknown"
        let header = "class \"\(typeName)\" as \(alias)\(genericsStr) "
            + "\(stereotype)\(macroAnnotation)\(moduleAnnotation)"
        return "\(header) { \(body) \n}"
    }

    func addLinking(context: DiagramContext) {
        for parent in linkParents() {
            context.addLinking(item: self, parent: parent.supertype, from: parent.scope)
        }
    }

    /// The parents `addLinking` draws an edge to: inherited types plus macro-synthesised
    /// conformances, then the supertypes merged extensions carried here (#76). The parser has
    /// already split a composition `A & B` into its parts, so an `&` left in a name is part of
    /// that one type, as in `Base<any P & Q>`. A carried one that ends where an edge before it
    /// does, as a conformance two `#if` clauses both declare, is left out by
    /// `DiagramContext.addLinking`, by the box it ends on rather than its name: two files can each
    /// declare their own `fileprivate protocol P`. Each comes with the scope its name is written
    /// in: this declaration's, the carrying extension's (#125), or for a macro's conformance a
    /// file of the module that declares the protocol, which names no member of a type around
    /// (#157) and imports nothing: the expansion writes `Observation.Observable`, which no
    /// target's own `Observable` shadows.
    func linkParents() -> [CarriedSupertype] {
        let explicit = inheritedTypes ?? []
        let synthetic = syntheticConformances(besides: explicit)
        let scope = DeclarationScope(of: self)
        return explicit.map { CarriedSupertype(supertype: $0, scope: scope) }
            + synthetic.map { conformance in
                let module = conformance.name.flatMap(MacroConformanceTable.module(declaring:))
                let macroScope = DeclarationScope(filePath: scope.filePath, module: module, imports: [])
                return CarriedSupertype(supertype: conformance, scope: macroScope)
            }
            + carriedSupertypes
    }

    /// The conformances this declaration's macro attributes add, leaving out those `explicit`
    /// already names.
    private func syntheticConformances(besides explicit: [SyntaxStructure]) -> [SyntaxStructure] {
        let explicitNames = Set(explicit.compactMap(\.name))
        var synthetic: [SyntaxStructure] = []
        for macroName in attributeNames {
            let conformances = MacroConformanceTable.syntheticConformances(for: macroName)
            for conformance in conformances where !explicitNames.contains(conformance) {
                synthetic.append(SyntaxStructure(name: conformance))
            }
        }
        return synthetic
    }

    private func members(context: DiagramContext) -> String {
        var members = ""

        guard let substructure = substructure, substructure.count > 0 else { return members }

        for sub in substructure {
            if let msig = member(element: sub, context: context) {
                members.appendAsNewLine(msig)
            }
        }

        return members
    }

    private func member(element: SyntaxStructure, context: DiagramContext) -> String? {
        guard let actualElement = renderableMember(from: element, context: context) else { return nil }

        var msig = "  "

        msig.addOrSkipMemberAccessLevelAttribute(for: actualElement, basedOn: context.configuration)

        msig += memberName(of: actualElement)

        if let memberSuffix = actualElement.memberSuffix {
            msig += " " + memberSuffix
        }

        return msig
    }

    private func memberName(of element: SyntaxStructure) -> String {
        guard let kind = element.kind, let name = element.name else { return "" }
        switch kind {
        case .functionMethodInstance:
            // Detect async/throws from typename field (SourceKitten encodes these in return type)
            let typeName = element.typename ?? ""
            let asyncLabel = typeName.contains("async") ? " async" : ""
            let throwsLabel = typeName.contains("throws") ? " throws" : ""
            return "\(name)\(asyncLabel)\(throwsLabel)"
        case .functionMethodStatic:
            let typeName = element.typename ?? ""
            let asyncLabel = typeName.contains("async") ? " async" : ""
            let throwsLabel = typeName.contains("throws") ? " throws" : ""
            return "{static} \(name)\(asyncLabel)\(throwsLabel)"
        case .varInstance:
            if let typename = element.typename {
                return "\(name) : \(typename)"
            } else {
                return "\(name)"
            }
        case .varStatic:
            if let typename = element.typename {
                return "{static} \(name) : \(typename)"
            } else {
                return "{static} \(name)"
            }
        case .enumelement:
            return "\(name)"
        default:
            return ""
        }
    }

    func skip(element: SyntaxStructure, basedOn configuration: Configuration) -> Bool {
        guard skip(element: self, basedOn: configuration.elements.exclude) == false else { return true }

        guard let elementKind = element.kind else { return true }

        if elementKind != .extension {
            let generateElementsWithAccessLevel: [ElementAccessibility] = configuration.elements
                .havingAccessLevel.compactMap { ElementAccessibility(orig: $0) }
            let effectiveAccessibility = accessibility ?? ElementAccessibility.internal
            guard generateElementsWithAccessLevel.contains(effectiveAccessibility) else { return true }
        }

        if configuration.elements.showExtensions.safelyUnwrap == .none, kind == .extension {
            return true
        }

        return false
    }

    func skip(element: SyntaxStructure, basedOn excludeElements: [String]?) -> Bool {
        element.isExcluded(byPatterns: excludeElements)
    }

    /// The `<…>` clause the emitters write after an element's name: an extension's bound
    /// arguments (`<Int>` for `extension Foo<Int>`), else a type's own parameters (`<T>`), or, for
    /// an element with no members, its first supertype's arguments (`<[Int]>` for
    /// `class D: Base<[Int]> {}`).
    func genericsStatement() -> String? {
        if let boundGenericArguments { return "<\(boundGenericArguments)>" }
        guard let substructure = substructure else {
            guard let parent = inheritedTypes?.first else { return nil }
            return parent.name?.getAngleBracketsWithContent()
        }
        let params = substructure.filter { $0.kind == ElementKind.genericTypeParam }
        var genParts: [String] = []
        for param in params {
            guard let name = param.name else { continue }
            if let typeName = param.inheritedTypes?[0].name {
                genParts.append("\(name): \(typeName)")
            } else {
                genParts.append("\(name)")
            }
        }
        let genStatement = genParts.joined(separator: "\\n")
        guard genStatement.count > 0 else { return nil }
        return "<\(genStatement)>"
    }
}
