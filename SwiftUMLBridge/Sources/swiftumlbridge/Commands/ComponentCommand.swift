import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct ComponentCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "component",
            abstract: """
            Generate a UML Component diagram from an SPM package — components are SPM \
            targets, edges come from target_dependencies, provided interfaces are public \
            Swift types per target.
            """,
            helpNames: [.short, .long]
        )

        @Option(help: "Path to a Package.swift directory.")
        var package: String

        @Option(help: "Diagram format. Options: plantuml, mermaid")
        var format: DiagramFormat?

        @Option(help: ArgumentHelp(
            "Output destination. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
            valueName: "output"
        ))
        var output: ClassDiagramOutput?

        @Flag(help: "Include test targets in the diagram (excluded by default).")
        var includeTestTargets: Bool = false

        mutating func run() async throws {
            let packageRoot = URL(fileURLWithPath: package)
            let description = try SPMPackageReader.describe(at: packageRoot)
            BridgeLogger.shared.info(
                "Loaded SPM package '\(description.name)' with \(description.targets.count) target(s)"
            )

            var configuration = Configuration.default
            if let format { configuration.format = format }

            let model = ComponentExtractor.extract(
                package: description,
                packageRoot: packageRoot,
                includeTestTargets: includeTestTargets
            )
            guard !model.isEmpty else {
                throw CLIError.componentModelNotFound
            }
            let script = ComponentScript(model: model, configuration: configuration)

            await output.present(script)
        }
    }
}
