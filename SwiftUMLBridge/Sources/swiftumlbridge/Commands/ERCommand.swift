import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension SwiftUMLBridgeCLI {
    struct ERCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "er",
            abstract: """
            Generate an Entity-Relationship diagram from SwiftData @Model classes \
            or Core Data .xcdatamodeld bundles
            """,
            helpNames: [.short, .long]
        )

        @Argument(help: "Paths to Swift source files or directories")
        var paths: [String] = []

        @OptionGroup var common: CommonDiagramOptions

        mutating func run() async throws {
            let bridgeConfig = common.resolvedConfiguration()

            let sourcePaths = paths.isEmpty ? ["."] : paths
            let generator = ERDiagramGenerator()
            let script = generator.generateScript(for: sourcePaths, with: bridgeConfig)

            if script.text.isEmpty {
                throw CLIError.erModelNotFound
            }

            await common.output.present(script)
        }
    }
}
