import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

@main
struct SwiftUMLBridgeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftumlbridge",
        abstract: "Generate architectural diagrams from Swift source code",
        version: SwiftUMLBridgeFramework.Version.current.value,
        subcommands: [
            ClassDiagramCommand.self, SequenceCommand.self,
            DepsCommand.self, ActivityCommand.self, StateCommand.self,
            ERCommand.self, ComponentCommand.self
        ],
        defaultSubcommand: ClassDiagramCommand.self
    )

    /// Runs the subcommand as `AsyncParsableCommand.main()` does, then says on stderr what the
    /// parsers were not given as written, whether the subcommand succeeded or not (#148).
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            SourceReadNoticeReporter.report()
        } catch {
            SourceReadNoticeReporter.report()
            exit(withError: error)
        }
    }
}
