import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("StateMachineGenerator")
struct StateMachineGeneratorTests {

    private func writeTemp(_ source: String, name: String = "Sample.swift") throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("state-machine-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent(name)
        try source.write(to: file, atomically: true, encoding: .utf8)
        return directory
    }

    private let trafficLightSource = """
    enum Light { case red, yellow, green }
    class TrafficLight {
        var state: Light = .red
        func advance() {
            switch self.state {
            case .red: self.state = .green
            case .green: self.state = .yellow
            case .yellow: self.state = .red
            }
        }
    }
    """

    @Test("findCandidates returns a candidate for the sample source")
    func findsCandidate() throws {
        let directory = try writeTemp(trafficLightSource)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generator = StateMachineGenerator()
        let candidates = generator.findCandidates(for: [directory.path])

        #expect(candidates.count == 1)
        #expect(candidates.first?.identifier == "TrafficLight.Light")
    }

    @Test("generateScript returns empty when identifier not found")
    func missingIdentifierReturnsEmpty() throws {
        let directory = try writeTemp(trafficLightSource)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generator = StateMachineGenerator()
        let script = generator.generateScript(
            for: [directory.path],
            stateIdentifier: "Nonexistent.Type"
        )

        #expect(script.text.isEmpty)
    }

    @Test("generateScript emits PlantUML for matching identifier")
    func emitsPlantUMLForIdentifier() throws {
        let directory = try writeTemp(trafficLightSource)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generator = StateMachineGenerator()
        let script = generator.generateScript(
            for: [directory.path],
            stateIdentifier: "TrafficLight.Light"
        )

        #expect(script.text.contains("@startuml"))
        #expect(script.text.contains("title TrafficLight.Light"))
        #expect(script.text.contains("red --> green : advance()"))
    }
}
