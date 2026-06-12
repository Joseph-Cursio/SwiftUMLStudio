import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

enum CLIError: Error, CustomStringConvertible {
    case invalidEntry
    case stateCandidateNotFound(identifier: String)
    case erModelNotFound
    case componentModelNotFound

    var description: String {
        switch self {
        case .invalidEntry:
            return "Entry must be in the form 'TypeName.methodName'"
        case .stateCandidateNotFound(let identifier):
            return "No state machine candidate '\(identifier)' was found in the sources."
        case .erModelNotFound:
            return "No persisted models (SwiftData @Model, Core Data, GRDB, SQLite.swift) were found in the sources."
        case .componentModelNotFound:
            return "No components were extracted from the SPM package. "
                + "Make sure `swift package describe` succeeds in the package directory."
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

        @Option(help: "macOS SDK path for type inference resolution")
        var sdk: String?

        @OptionGroup var common: CommonDiagramOptions

        mutating func run() async throws {
            let bridgeConfig = common.resolvedConfiguration()

            let (entryType, entryMethod) = try entry.parsedEntryPoint()

            let sourcePaths = paths.isEmpty ? ["."] : paths
            let script = SequenceDiagramGenerator().generateScript(
                for: sourcePaths,
                entryType: entryType,
                entryMethod: entryMethod,
                depth: depth,
                with: bridgeConfig
            )

            await common.output.present(script)
        }
    }
}
