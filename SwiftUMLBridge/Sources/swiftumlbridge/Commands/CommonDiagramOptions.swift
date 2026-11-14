import ArgumentParser
import SwiftUMLBridgeFramework

/// The `--format` / `--output` / `--config` triplet shared by every diagram
/// subcommand. Flattened into each command via `@OptionGroup`, so the
/// command-line surface is unchanged.
struct CommonDiagramOptions: ParsableArguments {
    @Option(help: "Diagram format.")
    var format: DiagramFormat?

    @Option(help: "Output destination.")
    var output: ClassDiagramOutput?

    @Option(help: "Path to custom configuration file")
    var config: String?

    /// Loads the configuration file (if any) and applies the `--format` override.
    ///
    /// - Throws: `CLIError.invalidConfiguration` when the `--config` file cannot be used.
    func resolvedConfiguration() throws -> Configuration {
        var bridgeConfig = try ConfigurationLoader().load(config)
        if let format {
            bridgeConfig.format = format
        }
        return bridgeConfig
    }
}
