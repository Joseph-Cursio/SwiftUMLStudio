import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct ERCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "er",
            abstract: "Generate an Entity-Relationship diagram from SwiftData @Model classes",
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @Option(help: "Diagram format. Options: plantuml, mermaid")
        var format: DiagramFormat?

        @Option(help: ArgumentHelp(
            "Output format. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
            valueName: "output"
        ))
        var output: ClassDiagramOutput?

        @Option(help: "Path to custom configuration file")
        var config: String?

        mutating func run() async throws {
            var bridgeConfig = ConfigurationProvider().getConfiguration(for: self.config)

            if let format {
                bridgeConfig.format = format
            }

            let sourcePaths = paths.isEmpty ? ["."] : paths
            let generator = ERDiagramGenerator()
            let script = generator.generateScript(for: sourcePaths, with: bridgeConfig)

            if script.text.isEmpty {
                throw CLIError.erModelNotFound
            }

            switch output {
            case .browserImageOnly:
                await BrowserPresenter(format: .png).present(script: script)
            case .consoleOnly:
                await ConsolePresenter().present(script: script)
            default:
                await BrowserPresenter(format: .default).present(script: script)
            }
        }
    }
}
