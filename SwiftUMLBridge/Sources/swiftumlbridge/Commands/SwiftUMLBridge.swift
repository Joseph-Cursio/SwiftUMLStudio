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
            ERCommand.self
        ],
        defaultSubcommand: ClassDiagramCommand.self
    )
}
