import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Read-from-disk integration tests for the state-machine pipeline.
/// Each test points `StateMachineGenerator` at one fixture file under
/// `TestFixtures/SampleProject/StateMachines/`, then exercises the full
/// path: file read → SwiftSyntax parse → `StateMachineExtractor` →
/// `StateMachineModel` → `StateScript` rendered as PlantUML / Mermaid.
///
/// The detector logic itself is covered by `StateMachineExtractorTests`
/// using inline source strings; these tests close the gap by also
/// exercising the disk-read + emitter path (and serving as a discovery
/// surface for the patterns we support).
@Suite("State-machine fixtures (on-disk integration)")
struct StateMachineFixtureTests {

    /// Locate the on-disk fixture path. `TestFixtures/SampleProject/...` lives
    /// at the repo root (a sibling of the SwiftUMLBridge package), so we walk
    /// up from `#filePath` five levels: ModelTests → SwiftUMLBridgeFrameworkTests
    /// → Tests → SwiftUMLBridge → repo root.
    private func fixturePath(_ name: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()  // ModelTests
            .deletingLastPathComponent()  // SwiftUMLBridgeFrameworkTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SwiftUMLBridge
            .deletingLastPathComponent()  // repo root
        return repoRoot
            .appendingPathComponent("TestFixtures/SampleProject/StateMachines")
            .appendingPathComponent(name)
            .path
    }

    private var generator: StateMachineGenerator { StateMachineGenerator() }

    // MARK: - Positive cases

    @Test("SimpleTrafficLight: detects classic 3-state enum + switch")
    func simpleTrafficLight() throws {
        let path = fixturePath("SimpleTrafficLight.swift")
        let candidates = generator.findCandidates(for: [path])
        let model = try #require(candidates.first { $0.hostType == "SimpleTrafficLight" })
        #expect(model.enumType == "Phase")
        #expect(Set(model.states.map(\.name)) == ["red", "green", "yellow"])

        let plantuml = generator.generateScript(
            for: [path], stateIdentifier: model.identifier, with: .default
        ).text
        #expect(plantuml.contains("@startuml"))
        #expect(plantuml.contains("red"))
        #expect(plantuml.contains("green"))
        #expect(plantuml.contains("yellow"))
        #expect(plantuml.contains("@enduml"))
    }

    @Test("LoadingStore: detects @Published enum inside ObservableObject")
    func loadingStore() throws {
        let path = fixturePath("LoadingStore.swift")
        let candidates = generator.findCandidates(for: [path])
        let model = try #require(candidates.first { $0.hostType == "LoadingStore" })
        #expect(model.enumType == "LoadState")
        #expect(Set(model.states.map(\.name)) == ["idle", "loading", "loaded", "failed"])
    }

    @Test("AsyncTaskActor: detects an actor + TaskState enum")
    func asyncTaskActor() throws {
        let path = fixturePath("AsyncTaskActor.swift")
        let candidates = generator.findCandidates(for: [path])
        let model = try #require(candidates.first { $0.hostType == "AsyncTaskActor" })
        #expect(model.enumType == "TaskState")
        #expect(Set(model.states.map(\.name)) == ["pending", "running", "succeeded", "failed"])
    }

    @Test("NavigationRouter: detects a SwiftUI route enum")
    func navigationRouter() throws {
        let path = fixturePath("NavigationRouter.swift")
        let candidates = generator.findCandidates(for: [path])
        let model = try #require(candidates.first { $0.hostType == "NavigationRouter" })
        #expect(model.enumType == "Route")
        #expect(Set(model.states.map(\.name)) == ["list", "detail", "settings"])
    }

    // MARK: - Negative case

    @Test("NotAStateMachine: discriminated union with associated values yields zero candidates")
    func notAStateMachine() {
        let path = fixturePath("NotAStateMachine.swift")
        let candidates = generator.findCandidates(for: [path])
        // The enum has associated values and is never self-assigned, so the
        // detector must reject it. Any candidate here is a regression.
        #expect(candidates.isEmpty)
    }

    // MARK: - Whole-directory pass

    @Test("scanning the whole StateMachines directory yields exactly the four positive cases")
    func wholeDirectory() {
        let directory = fixturePath("")  // strips filename, leaves dir
        let candidates = generator.findCandidates(for: [directory])
        let hosts = Set(candidates.map(\.hostType))
        #expect(hosts == ["SimpleTrafficLight", "LoadingStore", "AsyncTaskActor", "NavigationRouter"])
    }
}
