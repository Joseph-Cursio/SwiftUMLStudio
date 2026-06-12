import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

/// The `--format` / `--output` / `--config` triplet shared by every diagram
/// subcommand. Flattened into each command via `@OptionGroup`, so the
/// command-line surface is unchanged.
struct CommonDiagramOptions: ParsableArguments {
    @Option(help: "Diagram format. Options: plantuml, mermaid")
    var format: DiagramFormat?

    @Option(help: ArgumentHelp(
        "Output format. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
        valueName: "output"
    ))
    var output: ClassDiagramOutput?

    @Option(help: "Path to custom configuration file")
    var config: String?

    /// Loads the configuration file (if any) and applies the `--format` override.
    func resolvedConfiguration() -> Configuration {
        var bridgeConfig = ConfigurationProvider().getConfiguration(for: config)
        if let format {
            bridgeConfig.format = format
        }
        return bridgeConfig
    }
}

extension Optional where Wrapped == ClassDiagramOutput {
    /// The presenter selected by this output option (defaults to the browser).
    var presenter: any DiagramPresenting {
        switch self {
        case .browserImageOnly: return BrowserPresenter(format: .png)
        case .consoleOnly:      return ConsolePresenter()
        default:                return BrowserPresenter(format: .default)
        }
    }

    /// Present `script` using the presenter selected by this output option.
    func present(_ script: any DiagramOutputting) async {
        await presenter.present(script: script)
    }
}
