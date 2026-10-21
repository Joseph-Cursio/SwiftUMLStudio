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
            (system frameworks excluded); in --types each type is tagged \
            with the SPM target that declares it, or, for a type the \
            package only extends, the first target in path order that \
            extends it. \
            Overrides any positional `paths` arguments.
            """)
        var package: String?

        @OptionGroup var common: CommonDiagramOptions

        mutating func run() async throws {
            var bridgeConfig = try common.resolvedConfiguration()

            // Each flag sets only its own key, so the config file's other `elements` keys,
            // `exclude` among them, still apply. `--exclude` replaces the file's list.
            if publicOnly {
                bridgeConfig.elements.havingAccessLevel = [.open, .public]
            }

            if !exclude.isEmpty {
                bridgeConfig.elements.exclude = exclude
            }

            // `--modules` takes precedence; `--types` is also valid; default to types
            let mode: DepsMode = modules ? .modules : .types
            let generator = DependencyGraphGenerator()

            let script: DepsScript
            if let packagePath = package {
                let (packageRoot, description) = try packagePath.loadedPackage()
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
