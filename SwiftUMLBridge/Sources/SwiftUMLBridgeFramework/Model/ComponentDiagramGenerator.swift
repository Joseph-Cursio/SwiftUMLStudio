import Foundation

/// Generates Component diagram scripts from an SPM package description.
///
/// Today's implementation is package-driven only — there's no "component
/// diagram from a directory of Swift sources" entry because component
/// boundaries genuinely come from the SPM manifest. Studio integration is
/// deferred; the CLI's `swiftumlbridge component --package …` is the only
/// surface for v1.
public struct ComponentDiagramGenerator: ComponentDiagramGenerating, @unchecked Sendable {
    public init() {}

    public func generateScript(
        forPackage description: SPMPackageDescription,
        packageRoot: URL,
        with configuration: Configuration = .default
    ) -> ComponentScript {
        let model = ComponentExtractor.extract(
            package: description,
            packageRoot: packageRoot
        )
        guard !model.isEmpty else { return .empty }
        return ComponentScript(model: model, configuration: configuration)
    }
}
