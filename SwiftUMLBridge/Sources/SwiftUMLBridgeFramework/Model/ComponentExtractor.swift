import Foundation

/// Builds a `ComponentModel` from a parsed SPM package description: each
/// non-test target becomes one `Component`, public Swift types in the target
/// become its provided interfaces, and `target_dependencies` become the
/// directed wiring edges. Test targets are excluded by default since they
/// rarely belong on an architecture diagram.
public enum ComponentExtractor {

    /// Map an `SPMPackageDescription` (already loaded by `SPMPackageReader`)
    /// to a `ComponentModel`. Per-target public types are listed via
    /// `ClassDiagramGenerator.analyzeTypes` over each target's source paths.
    public static func extract(
        package description: SPMPackageDescription,
        packageRoot: URL,
        analyzer: ClassDiagramGenerator = ClassDiagramGenerator(),
        includeTestTargets: Bool = false
    ) -> ComponentModel {
        let visibleTargets = description.targets.filter {
            includeTestTargets || $0.kind != .test
        }
        let visibleNames = Set(visibleTargets.map(\.name))

        var components: [Component] = []
        for target in visibleTargets {
            let absolutePaths = target.sources.map {
                packageRoot
                    .appendingPathComponent(target.path)
                    .appendingPathComponent($0)
                    .path
            }
            let publicTypes = absolutePaths.isEmpty
                ? []
                : analyzer.analyzeTypes(for: absolutePaths)
                    .filter { ($0.accessLevel ?? "internal") == "public" || ($0.accessLevel ?? "internal") == "open" }
                    .map(\.name)
                    .sorted()
            components.append(Component(
                name: target.name,
                kind: target.kind,
                providedInterfaces: publicTypes
            ))
        }

        var dependencies: [ComponentDependency] = []
        for target in visibleTargets {
            for dependencyName in target.dependencies where visibleNames.contains(dependencyName) {
                dependencies.append(ComponentDependency(from: target.name, to: dependencyName))
            }
        }

        return ComponentModel(components: components, dependencies: dependencies)
    }
}
