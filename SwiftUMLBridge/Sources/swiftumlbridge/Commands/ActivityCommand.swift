import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct ActivityCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "activity",
            abstract: "Generate a control-flow activity diagram for a Swift entry function",
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @Option(help: "Entry point as Type.method (e.g. MyClass.myMethod)")
        var entry: String

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

            let parts = entry.split(separator: ".").map(String.init)
            guard parts.count == 2 else { throw CLIError.invalidEntry }
            let entryType = parts[0]
            let entryMethod = parts[1]

            let sourcePaths = paths.isEmpty ? ["."] : paths
            let script = ActivityDiagramGenerator().generateScript(
                for: sourcePaths,
                entryType: entryType,
                entryMethod: entryMethod,
                with: bridgeConfig
            )

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
