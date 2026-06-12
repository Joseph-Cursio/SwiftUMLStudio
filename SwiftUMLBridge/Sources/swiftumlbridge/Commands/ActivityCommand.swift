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

        @OptionGroup var common: CommonDiagramOptions

        mutating func run() async throws {
            let bridgeConfig = common.resolvedConfiguration()

            let (entryType, entryMethod) = try entry.parsedEntryPoint()

            let sourcePaths = paths.isEmpty ? ["."] : paths
            let script = ActivityDiagramGenerator().generateScript(
                for: sourcePaths,
                entryType: entryType,
                entryMethod: entryMethod,
                with: bridgeConfig
            )

            await common.output.present(script)
        }
    }
}
