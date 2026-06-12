import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct ClassDiagramCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "classdiagram",
            abstract: "Generate PlantUML or Mermaid class diagram from Swift sources",
            helpNames: [.short, .long]
        )

        // swiftlint:disable:next line_length
        @Option(help: "Path to custom configuration file (otherwise searches for '.swiftumlbridge.yml' in current directory)")
        var config: String?

        @Option(help: "Paths to source files to exclude. Takes precedence over arguments.")
        var exclude = [String]()

        @Option(help: ArgumentHelp(
            "Output format. Options: \(ClassDiagramOutput.allCases.map(\.rawValue).joined(separator: ", "))",
            valueName: "format"
        ))
        var output: ClassDiagramOutput?

        @Option(help: "Diagram format. Options: plantuml, mermaid")
        var format: DiagramFormat?

        @Option(help: "macOS SDK path for type inference resolution (e.g. `$(xcrun --show-sdk-path -sdk macosx)`)")
        var sdk: String?

        @Option(help: """
            Path to a Package.swift directory. Activates module-aware mode: \
            each type is tagged with its SPM target and rendered with a \
            module stereotype. Overrides any positional `paths` arguments.
            """)
        var package: String?

        @Flag(help: "Decide if/how Swift extensions appear in the diagram")
        var extensionVisualization: ExtensionVisualizationFlag = .showExtensions

        @Flag(help: "Enable verbose logging")
        var verbose: Bool = false

        @Argument(help: "Paths to Swift source files or directories")
        var paths = [String]()

        mutating func run() async throws {
            var bridgeConfig = ConfigurationProvider().getConfiguration(for: self.config)

            if !exclude.isEmpty {
                bridgeConfig.files.exclude = exclude
            }

            if bridgeConfig.elements.showExtensions == nil {
                switch extensionVisualization {
                case .hideExtensions:
                    bridgeConfig.elements.showExtensions = ExtensionVisualization.none
                case .mergeExtensions:
                    bridgeConfig.elements.showExtensions = .merged
                case .showExtensions:
                    bridgeConfig.elements.showExtensions = .all
                }
            }

            if let format {
                bridgeConfig.format = format
            }

            BridgeLogger.shared.info("SDK: \(sdk ?? "no SDK path provided")")

            let generator = ClassDiagramGenerator()
            let presenter = output.presenter

            if let packagePath = package {
                let packageRoot = URL(fileURLWithPath: packagePath)
                let description = try SPMPackageReader.describe(at: packageRoot)
                BridgeLogger.shared.info(
                    "Loaded SPM package '\(description.name)' with \(description.targets.count) target(s)"
                )
                let script = generator.generateScript(
                    forPackage: description,
                    packageRoot: packageRoot,
                    with: bridgeConfig,
                    sdkPath: sdk
                )
                await presenter.present(script: script)
                return
            }

            let directory = FileManager.default.currentDirectoryPath
            let files = FileCollector().getFiles(for: paths, in: directory, honoring: bridgeConfig.files)
            await generator.generate(
                for: files.map(\.path), with: bridgeConfig,
                presentedBy: presenter, sdkPath: sdk
            )
        }
    }
}

extension ClassDiagramOutput: ExpressibleByArgument {}
extension DiagramFormat: ExpressibleByArgument {}

enum ExtensionVisualizationFlag: EnumerableFlag {
    case hideExtensions
    case mergeExtensions
    case showExtensions
}
