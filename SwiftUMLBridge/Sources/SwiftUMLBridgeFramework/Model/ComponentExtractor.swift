import Foundation

/// Builds a `ComponentModel` from a parsed SPM package description: each
/// non-test target becomes one `Component`, public Swift types in the target
/// become its provided interfaces, and `target_dependencies` become the
/// directed wiring edges. Test targets are excluded by default since they
/// rarely belong on an architecture diagram.
public enum ComponentExtractor {

    /// Map an `SPMPackageDescription` (already loaded by `SPMPackageReader`)
    /// to a `ComponentModel`. Per-target public types are listed via
    /// `ClassDiagramGenerating.analyzeTypes` over each target's source paths.
    ///
    /// `analyzer` is the protocol rather than the concrete generator, which is what every other
    /// entry point in this package already takes — `ProjectAnalyzer` and `DiagramViewModel` both
    /// declare `classGenerator: any ClassDiagramGenerating` and the package ships
    /// `MockClassGenerator` against it. This one had been left concrete, so it was the single
    /// site where a caller could not substitute the generator the others let them swap.
    public static func extract(
        package description: SPMPackageDescription,
        packageRoot: URL,
        analyzer: any ClassDiagramGenerating = ClassDiagramGenerator(),
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
