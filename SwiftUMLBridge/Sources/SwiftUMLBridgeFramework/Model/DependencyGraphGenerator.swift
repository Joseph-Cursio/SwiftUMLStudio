import Foundation

/// Determines whether to generate a type-level or module-level dependency graph.
public enum DepsMode: String, CaseIterable, Sendable {
    /// Type-to-type edges from inheritance and protocol conformance.
    case types = "Types"
    /// Module-to-module edges from `import` statements.
    case modules = "Modules"
}

/// Generates dependency graph scripts from Swift source files.
public struct DependencyGraphGenerator {
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

    // MARK: - Types mode

    private func extractTypeEdges(from files: [URL], configuration: Configuration) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []

        for file in files {
            guard let structure = SyntaxStructure.create(from: file),
                  let items = structure.substructure else { continue }

            for item in items {
                guard !shouldSkip(element: item, configuration: configuration),
                      let name = item.name,
                      let inheritedTypes = item.inheritedTypes,
                      !inheritedTypes.isEmpty else { continue }

                // Classes use `.inherits` for their first parent (likely a superclass);
                // structs, enums, actors, and protocols always use `.conforms`.
                let edgeKind: DependencyEdgeKind = (item.kind == .class) ? .inherits : .conforms

                for parent in inheritedTypes {
                    // Split compound conformance types ("A & B") into individual edges
                    let parentNames: [String]
                    if let parentName = parent.name, parentName.contains("&") {
                        parentNames = parentName
                            .components(separatedBy: "&")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    } else if let parentName = parent.name {
                        parentNames = [parentName]
                    } else {
                        continue
                    }

                    for parentName in parentNames {
                        guard !shouldExclude(name: parentName, configuration: configuration) else { continue }
                        edges.append(DependencyEdge(from: name, to: parentName, kind: edgeKind))
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
