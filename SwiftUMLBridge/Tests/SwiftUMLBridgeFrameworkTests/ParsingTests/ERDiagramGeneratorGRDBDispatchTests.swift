import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ERDiagramGenerator merges GRDB output with SwiftData / Core Data")
struct ERDiagramGeneratorGRDBDispatchTests {

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/SampleProject/Persistence")
            .appendingPathComponent(name)
            .path
    }

    @Test("GRDB Swift source produces a Mermaid erDiagram via the generator")
    func dispatchesGRDBToMermaid() throws {
        let path = fixturePath("GRDBPlayer.swift")
        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ERDiagramGenerator().generateScript(for: [path], with: configuration)
        #expect(script.text.contains("erDiagram"))
        #expect(script.text.contains("Player"))
        #expect(script.text.contains("Team"))
        #expect(script.text.contains("Score"))
    }
}
