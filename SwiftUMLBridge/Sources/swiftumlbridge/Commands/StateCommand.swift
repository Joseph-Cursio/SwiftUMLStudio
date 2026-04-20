import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct StateCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "state",
            abstract: "Generate a state machine diagram from Swift enum state patterns",
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @Option(
            name: [.long, .customShort("s")],
            help: "State machine identifier as HostType.EnumType (e.g. TrafficLight.Color)"
        )
        var state: String?

        @Flag(
            name: [.long, .customShort("l")],
            help: "List candidate state machines and exit"
        )
        var list: Bool = false

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
            let generator = StateMachineGenerator()

            if list || state == nil {
                printCandidates(generator.findCandidates(for: sourcePaths))
                return
            }

            guard let identifier = state else { return }

            let script = generator.generateScript(
                for: sourcePaths,
                stateIdentifier: identifier,
                with: bridgeConfig
            )

            if script.text.isEmpty {
                throw CLIError.stateCandidateNotFound(identifier: identifier)
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

        private func printCandidates(_ candidates: [StateMachineModel]) {
            if candidates.isEmpty {
                print("No state machine candidates found.")
                return
            }
            print("Candidate state machines:")
            for candidate in candidates {
                let transitions = candidate.transitions.count
                let plural = transitions == 1 ? "transition" : "transitions"
                print("  \(candidate.identifier) "
                    + "[\(candidate.confidence.rawValue), \(transitions) \(plural)]")
                for note in candidate.notes {
                    print("    ↳ \(note)")
                }
            }
            print("\nRun again with --state <identifier> to render one.")
        }
    }
}
