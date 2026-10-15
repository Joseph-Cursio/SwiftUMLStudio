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

    /// `--state` is typed in, so it may escape a name the source spells plainly, or the reverse.
    @Test("generateScript finds a candidate however its names are escaped", arguments: ["Lamp.Light", "`Lamp`.`Light`"])
    func escapedIdentifierFindsCandidate(stateIdentifier: String) throws {
        let source = trafficLightSource
            .replacingOccurrences(of: "enum Light", with: "enum `Light`")
            .replacingOccurrences(of: "class TrafficLight", with: "class `Lamp`")
        let directory = try writeTemp(source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let generator = StateMachineGenerator()
        #expect(generator.findCandidates(for: [directory.path]).map(\.identifier) == ["Lamp.Light"])
        let script = generator.generateScript(for: [directory.path], stateIdentifier: stateIdentifier)
        #expect(script.text.contains("@startuml"))
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

    @Test("findCandidates merges same host+enum across files")
    func mergesAcrossFiles() throws {
        // Two files that each independently contain the enum declaration and the
        // host type. This mirrors a (rare but possible) project where a type is
        // conditionally compiled or split for target-specific reasons. Each file
        // contributes one transition; the merge should union them. File 2 also
        // has a stray unguarded assignment that surfaces as a low-confidence
        // partial — merging should drag the overall confidence down.
        let source1 = """
        enum Light { case red, green }
        class TrafficLight {
            var state: Light = .red
            func goGreen() {
                switch self.state {
                case .red: self.state = .green
                case .green: break
                }
            }
        }
        """
        let source2 = """
        enum Other { case idle }
        class Bystander {
            var state: Other = .idle
            func nudge() {
                self.state = .idle
            }
        }
        enum Light { case red, green }
        class TrafficLight {
            var state: Light = .red
            func goRed() {
                switch self.state {
                case .green: self.state = .red
                case .red: break
                }
            }
        }
        """
        let directory = try writeTemp(source1, name: "File1.swift")
        defer { try? FileManager.default.removeItem(at: directory) }
        try source2.write(
            to: directory.appendingPathComponent("File2.swift"),
            atomically: true, encoding: .utf8
        )

        let generator = StateMachineGenerator()
        let candidates = generator.findCandidates(for: [directory.path])

        let merged = candidates.first(where: { $0.identifier == "TrafficLight.Light" })
        #expect(merged != nil)
        #expect(merged?.transitions.count == 2, "merged transitions should union across files")
        #expect(merged?.transitions.contains(where: { $0.from == "red" && $0.toState == "green" }) == true)
        #expect(merged?.transitions.contains(where: { $0.from == "green" && $0.toState == "red" }) == true)

        let lowConfidence = candidates.first(where: { $0.identifier == "Bystander.Other" })
        #expect(lowConfidence?.confidence == .low)
    }
}
