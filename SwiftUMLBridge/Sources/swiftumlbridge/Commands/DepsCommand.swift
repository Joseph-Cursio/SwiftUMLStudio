import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct DepsCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "deps",
            abstract: "Generate a dependency graph from Swift source files",
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @Flag(help: "Generate a module-level graph from import statements")
        var modules: Bool = false

        @Flag(help: "Generate a type-level graph from inheritance and conformance (default)")
        var types: Bool = false

        @Flag(help: "Include only public and open types")
        var publicOnly: Bool = false

        @Option(help: "Exclude types or modules matching these patterns")
        var exclude: [String] = []

        @Option(help: """
            Path to a Package.swift directory. Activates module-aware mode: \
            in --modules each SPM target_dependencies pair becomes an edge \
            (system frameworks excluded); in --types each inheritance / \
            conformance edge is tagged with the owning SPM target. \
            Overrides any positional `paths` arguments.
            """)
        var package: String?

        @OptionGroup var common: CommonDiagramOptions

        mutating func run() async throws {
            var bridgeConfig = common.resolvedConfiguration()

            if publicOnly {
                bridgeConfig.elements = ElementOptions(
                    havingAccessLevel: [.open, .public],
                    showMembersWithAccessLevel: bridgeConfig.elements.showMembersWithAccessLevel
                )
            }

            if !exclude.isEmpty {
                bridgeConfig.elements = ElementOptions(
                    havingAccessLevel: bridgeConfig.elements.havingAccessLevel,
                    showMembersWithAccessLevel: bridgeConfig.elements.showMembersWithAccessLevel,
                    exclude: exclude
                )
            }

            // `--modules` takes precedence; `--types` is also valid; default to types
            let mode: DepsMode = modules ? .modules : .types
            let generator = DependencyGraphGenerator()

            let script: DepsScript
            if let packagePath = package {
                let packageRoot = URL(fileURLWithPath: packagePath)
                let description = try SPMPackageReader.describe(at: packageRoot)
                BridgeLogger.shared.info(
                    "Loaded SPM package '\(description.name)' with \(description.targets.count) target(s)"
                )
                script = generator.generateScript(
                    forPackage: description,
                    packageRoot: packageRoot,
                    mode: mode,
                    with: bridgeConfig
                )
            } else {
                let sourcePaths = paths.isEmpty ? ["."] : paths
                script = generator.generateScript(
                    for: sourcePaths,
                    mode: mode,
                    with: bridgeConfig
                )
            }

            await common.output.present(script)
        }
    }
}
