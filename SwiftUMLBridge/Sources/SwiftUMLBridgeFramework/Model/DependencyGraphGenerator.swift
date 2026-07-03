import Foundation

/// Determines whether to generate a type-level or module-level dependency graph.
public enum DepsMode: String, CaseIterable, Sendable {
    /// Type-to-type edges from inheritance and protocol conformance.
    case types = "Types"
    /// Module-to-module edges from `import` statements.
    case modules = "Modules"
}

/// Generates dependency graph scripts from Swift source files.
public struct DependencyGraphGenerator: DependencyGraphGenerating, @unchecked Sendable {
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
            edges = extractModuleEdges(from: files)
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
            return extractModuleEdges(from: files)
        }
    }

    /// Generate a module-aware dependency graph from a parsed SPM package
    /// description. In `.modules` mode each target's `target_dependencies`
    /// become edges directly (authoritative — no source-level import parse),
    /// and each node is tagged with its target kind (`<<library>>` /
    /// `<<executable>>`) so emitters can stereotype them. In `.types` mode
    /// each inheritance/conformance edge is tagged with the owning module of
    /// the source type (and the parent type's module when it lives in the
    /// same package). Test targets are excluded.
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
            edges = extractModuleEdges(forPackage: description)
            kinds = Dictionary(
                uniqueKeysWithValues: description.targets
                    .filter { $0.kind != .test }
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
        var edges: [DependencyEdge] = []

        for file in files {
            guard let structure = SyntaxStructure.create(from: file),
                  let items = structure.substructure else { continue }

            for item in items {
                guard let basis = typeEdgeBasis(for: item, configuration: configuration) else { continue }
                for parent in basis.inheritedTypes {
                    for parentName in parentNames(from: parent) {
                        guard !shouldExclude(name: parentName, configuration: configuration) else { continue }
                        edges.append(DependencyEdge(from: basis.name, to: parentName, kind: basis.edgeKind))
                    }
                }
            }
        }

        return edges
    }

    // MARK: - Modules mode

    private func extractModuleEdges(from files: [URL]) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []

        for file in files {
            let sourceModule = file.deletingLastPathComponent().lastPathComponent
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let importEdges = ImportExtractor.extract(from: source, sourceModule: sourceModule)
            for importEdge in importEdges {
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

    private func extractModuleEdges(
        forPackage description: SPMPackageDescription
    ) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []
        let internalTargets = Set(
            description.targets
                .filter { $0.kind != .test }
                .map(\.name)
        )

        for target in description.targets where target.kind != .test {
            for dependency in target.dependencies {
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
        let pathToModule = description.sourceFileToModuleMap(packageRoot: packageRoot)

        // First pass: index every parsed type by name so we can resolve the
        // owning module of a parent type for cross-module `toModule` tagging.
        var typeOwners: [String: String] = [:]
        var parsedItems: [(item: SyntaxStructure, module: String)] = []
        for (path, module) in pathToModule {
            let url = URL(fileURLWithPath: path)
            guard let items = SyntaxStructure
                .create(from: url, sdkPath: sdkPath, module: module)?.substructure
            else { continue }
            for item in items {
                if let name = item.name {
                    typeOwners[name] = module
                }
                parsedItems.append((item, module))
            }
        }

        var edges: [DependencyEdge] = []
        for (item, module) in parsedItems {
            guard let basis = typeEdgeBasis(for: item, configuration: configuration) else { continue }
            for parent in basis.inheritedTypes {
                for parentName in parentNames(from: parent) {
                    guard !shouldExclude(name: parentName, configuration: configuration) else { continue }
                    edges.append(DependencyEdge(
                        from: basis.name,
                        to: parentName,
                        kind: basis.edgeKind,
                        fromModule: module,
                        toModule: typeOwners[parentName]
                    ))
                }
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

    /// Splits an inherited-type entry into individual parent names, expanding
    /// `A & B` composition clauses. Returns an empty array for an unnamed entry.
    private func parentNames(from parent: SyntaxStructure) -> [String] {
        guard let parentName = parent.name else { return [] }
        guard parentName.contains("&") else { return [parentName] }
        return parentName
            .components(separatedBy: "&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Filtering helpers

    private func shouldSkip(element: SyntaxStructure, configuration: Configuration) -> Bool {
        guard let kind = element.kind else { return true }
        let processableKinds: [ElementKind] = [.class, .struct, .extension, .enum, .protocol, .actor]
        guard processableKinds.contains(kind) else { return true }

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

    private func shouldExclude(name: String, configuration: Configuration) -> Bool {
        guard let excludePatterns = configuration.elements.exclude else { return false }
        return excludePatterns.contains(where: { name.isMatching(searchPattern: $0) })
    }
}
