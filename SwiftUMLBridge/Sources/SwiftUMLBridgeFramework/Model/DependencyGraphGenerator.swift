import Foundation

/// Determines whether to generate a type-level or module-level dependency graph.
public enum DepsMode: String, CaseIterable, Sendable {
    /// Type-to-type edges from inheritance and protocol conformance.
    case types = "Types"
    /// Module-to-module edges from `import` statements.
    case modules = "Modules"
}

/// Generates dependency graph scripts from Swift source files.
public struct DependencyGraphGenerator: DependencyGraphGenerating, Sendable {
    public init() {}

    /// Generate a `DepsScript` from Swift files at the given paths.
    ///
    /// - Parameters:
    ///   - paths: Paths to Swift source files or directories.
    ///   - mode: Whether to build a type-level or module-level graph.
    ///   - configuration: Diagram configuration (format, filters, etc.)
    /// - Returns: A rendered `DepsScript`.
    public func generateScript(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration = .default
    ) -> DepsScript {
        let files = FileCollector().getFiles(for: paths)
        let edges: [DependencyEdge]

        switch mode {
        case .types:
            edges = extractTypeEdges(from: files, configuration: configuration)
        case .modules:
            edges = extractModuleEdges(from: files, configuration: configuration)
        }

        let model = DependencyGraphModel(edges: edges)
        return DepsScript(model: model, configuration: configuration)
    }

    /// Extract raw dependency edges without rendering to diagram text.
    public func extractEdges(
        for paths: [String],
        mode: DepsMode,
        with configuration: Configuration = .default
    ) -> [DependencyEdge] {
        let files = FileCollector().getFiles(for: paths)
        switch mode {
        case .types:
            return extractTypeEdges(from: files, configuration: configuration)
        case .modules:
            return extractModuleEdges(from: files, configuration: configuration)
        }
    }

    /// Generate a module-aware dependency graph from a parsed SPM package
    /// description. In `.modules` mode each target's `target_dependencies`
    /// become edges directly (authoritative — no source-level import parse),
    /// and each node is tagged with its target kind (`<<library>>` /
    /// `<<executable>>`) so emitters can stereotype them. In `.types` mode
    /// each end of an inheritance/conformance edge is tagged with its type's
    /// module (`PackageTypeOwners`): the target that declares the type or,
    /// for a type no target declares, the first target in path order that
    /// extends it. So an extension's edge carries its type's module, not
    /// necessarily its own. Test targets are excluded.
    public func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        mode: DepsMode,
        with configuration: Configuration = .default,
        sdkPath: String? = nil
    ) -> DepsScript {
        let edges: [DependencyEdge]
        let kinds: [String: SPMTargetDescription.Kind]

        switch mode {
        case .modules:
            edges = extractModuleEdges(forPackage: description, configuration: configuration)
            kinds = Dictionary(
                uniqueKeysWithValues: description.targets
                    .filter { $0.kind != .test && !shouldExclude(name: $0.name, configuration: configuration) }
                    .map { ($0.name, $0.kind) }
            )
        case .types:
            edges = extractTypeEdges(
                forPackage: description,
                packageRoot: packageRoot,
                configuration: configuration,
                sdkPath: sdkPath
            )
            kinds = [:]
        }

        let model = DependencyGraphModel(edges: edges, targetKinds: kinds)
        return DepsScript(model: model, configuration: configuration)
    }

    // MARK: - Types mode

    private func extractTypeEdges(from files: [URL], configuration: Configuration) -> [DependencyEdge] {
        // Every file is parsed before any edge is drawn, so a typealias in one file is followed
        // from all the others (#125).
        let items = files.flatMap { SyntaxStructure.create(from: $0)?.substructure ?? [] }
        let aliases = TypeAliasResolver(items: items)
        var edges: [DependencyEdge] = []
        for item in items {
            guard let basis = typeEdgeBasis(for: item, configuration: configuration) else { continue }
            for parent in basis.inheritedTypes {
                guard let parentName = supertypeName(
                    of: parent, in: item, aliases: aliases, configuration: configuration
                ) else { continue }
                edges.append(DependencyEdge(from: basis.name, to: parentName, kind: basis.edgeKind))
            }
        }
        return edges
    }

    /// The name `item`'s edge to its supertype `parent` ends on: the type it comes to where
    /// `item` writes it, so `struct S: Q` after `typealias Q = Proto` ends on `Proto` (#125).
    /// `nil` when the name as written, or the type it comes to, is excluded.
    private func supertypeName(
        of parent: SyntaxStructure, in item: SyntaxStructure, aliases: TypeAliasResolver,
        configuration: Configuration
    ) -> String? {
        guard let written = parent.name, !shouldExclude(name: written, configuration: configuration) else {
            return nil
        }
        let resolved = aliases.resolve(written, from: DeclarationScope(of: item))
        return shouldExclude(name: resolved, configuration: configuration) ? nil : resolved
    }

    // MARK: - Modules mode

    /// An import edge is dropped when either module matches `elements.exclude` (#161).
    private func extractModuleEdges(from files: [URL], configuration: Configuration) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []

        for file in files {
            let sourceModule = file.deletingLastPathComponent().lastPathComponent
            guard !shouldExclude(name: sourceModule, configuration: configuration),
                  let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let importEdges = ImportExtractor.extract(from: source, sourceModule: sourceModule, file: file)
            for importEdge in importEdges
            where !shouldExclude(name: importEdge.importedModule, configuration: configuration) {
                edges.append(DependencyEdge(
                    from: importEdge.sourceModule,
                    to: importEdge.importedModule,
                    kind: .imports
                ))
            }
        }

        return edges
    }

    // MARK: - Package mode

    /// An excluded target, and every edge to or from it, is left out (#161).
    private func extractModuleEdges(
        forPackage description: SPMPackageDescription,
        configuration: Configuration
    ) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []
        let internalTargets = Set(
            description.targets
                .filter { $0.kind != .test }
                .map(\.name)
        )

        for target in description.targets
        where target.kind != .test && !shouldExclude(name: target.name, configuration: configuration) {
            for dependency in target.dependencies
            where !shouldExclude(name: dependency, configuration: configuration) {
                let toModule = internalTargets.contains(dependency) ? dependency : nil
                edges.append(DependencyEdge(
                    from: target.name,
                    to: dependency,
                    kind: .imports,
                    fromModule: target.name,
                    toModule: toModule
                ))
            }
        }

        return edges
    }

    private func extractTypeEdges(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        configuration: Configuration,
        sdkPath: String?
    ) -> [DependencyEdge] {
        // First pass: record the module of every type the package declares or
        // extends, so each edge can carry the module of both its ends. The
        // declarations' imports are widened with `@_exported` re-exports, as
        // the class diagram reads them.
        var owners = PackageTypeOwners()
        let files = description.sourceFilesInPathOrder(packageRoot: packageRoot).map { file in
            (url: URL(fileURLWithPath: file.path), module: Optional(file.module))
        }
        let parsedItems = SyntaxStructure.declarations(inPackageFiles: files, sdkPath: sdkPath)
        for item in parsedItems {
            if let module = item.module { owners.record(item, in: module) }
        }

        let aliases = TypeAliasResolver(items: parsedItems)
        var edges: [DependencyEdge] = []
        for item in parsedItems {
            guard let basis = typeEdgeBasis(for: item, configuration: configuration) else { continue }
            for parent in basis.inheritedTypes {
                guard let parentName = supertypeName(
                    of: parent, in: item, aliases: aliases, configuration: configuration
                ) else { continue }
                edges.append(DependencyEdge(
                    from: basis.name,
                    to: parentName,
                    kind: basis.edgeKind,
                    fromModule: owners.module(of: basis.name),
                    toModule: owners.module(of: parentName)
                ))
            }
        }

        return edges
    }

    /// Common per-item gate for type-edge extraction: apply the skip filter, then
    /// return the element name, its non-empty inherited types, and the edge kind.
    /// Classes inherit from their first parent; structs, enums, actors, and
    /// protocols always conform. Returns `nil` when the item yields no edges.
    private func typeEdgeBasis(
        for item: SyntaxStructure,
        configuration: Configuration
    ) -> TypeEdgeBasis? {
        guard !shouldSkip(element: item, configuration: configuration),
              let name = item.name,
              let inheritedTypes = item.inheritedTypes,
              !inheritedTypes.isEmpty else { return nil }
        let edgeKind: DependencyEdgeKind = (item.kind == .class) ? .inherits : .conforms
        return TypeEdgeBasis(name: name, inheritedTypes: inheritedTypes, edgeKind: edgeKind)
    }

    /// The inputs a single declaration contributes to type-edge extraction:
    /// its name, its non-empty inherited types, and whether those are
    /// inheritance or conformance edges.
    private struct TypeEdgeBasis {
        let name: String
        let inheritedTypes: [SyntaxStructure]
        let edgeKind: DependencyEdgeKind
    }

    // MARK: - Filtering helpers

    func shouldSkip(element: SyntaxStructure, configuration: Configuration) -> Bool {
        guard let kind = element.kind else { return true }
        guard ElementKind.processable.contains(kind) else { return true }

        // Access-level filtering (--public-only maps to configuration.elements.havingAccessLevel)
        if kind != .extension {
            let allowed: [ElementAccessibility] = configuration.elements
                .havingAccessLevel.compactMap { ElementAccessibility(orig: $0) }
            let effective = element.accessibility ?? ElementAccessibility.internal
            guard allowed.contains(effective) else { return true }
        }

        // Name exclusion
        if let name = element.name {
            guard !shouldExclude(name: name, configuration: configuration) else { return true }
        }

        return false
    }

    /// Whether `name`, a type or module, matches `elements.exclude` (`deps --exclude`).
    func shouldExclude(name: String, configuration: Configuration) -> Bool {
        guard let excludePatterns = configuration.elements.exclude else { return false }
        // Names are read as Swift reads them (#123), so a pattern is too: `` `Base` `` is `Base`.
        return excludePatterns.contains(where: { name.isMatching(searchPattern: $0.canonicalDottedName) })
    }
}
