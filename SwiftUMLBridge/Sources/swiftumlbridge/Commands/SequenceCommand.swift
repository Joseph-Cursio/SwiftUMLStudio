import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

enum CLIError: Error, CustomStringConvertible {
    case invalidEntry
    case stateCandidateNotFound(identifier: String)
    case erModelNotFound

    var description: String {
        switch self {
        case .invalidEntry:
            return "Entry must be in the form 'TypeName.methodName'"
        case .stateCandidateNotFound(let identifier):
            return "No state machine candidate '\(identifier)' was found in the sources."
        case .erModelNotFound:
            return "No SwiftData @Model classes were found in the sources."
        }
    }
}

extension SwiftUMLBridgeCLI {
    struct SequenceCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sequence",
            abstract: "Generate a sequence diagram from a Swift entry point",
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @Option(help: "Entry point as Type.method (e.g. MyClass.myMethod)")
        var entry: String

        @Option(help: "Max call depth (default: 3)")
        var depth: Int = 3

        @Option(help: "Diagram format. Options: plantuml, mermaid")
        var format: DiagramFormat?

        @Option(help: ArgumentHelp(
            "Output format. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
            valueName: "output"
        ))
        var output: ClassDiagramOutput?

        @Option(help: "Path to custom configuration file")
        var config: String?

        @Option(help: "macOS SDK path for type inference resolution")
        var sdk: String?

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
            let script = SequenceDiagramGenerator().generateScript(
                for: sourcePaths,
                entryType: entryType,
                entryMethod: entryMethod,
                depth: depth,
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
