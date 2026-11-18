//
//  BackgroundScanTests.swift
//  SwiftUMLStudioTests
//
//  The entry-point and state-machine scans run off the main actor.
//

import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

/// `refreshEntryPoints()` and `refreshStateMachines()` parse the selection in a background task
/// and publish on the main actor, dropping a result that was cancelled or whose selection has
/// changed since (#281). Parsing on the main actor froze the window for as long as a large
/// selection took.
@Suite("Entry-point and state-machine scans run in the background", .timeLimit(.minutes(1))) @MainActor
struct BackgroundScanTests {

    private static let entrySourceA = "struct Alpha { func run() {} }"
    private static let entrySourceB = "struct Beta { func go() {} }"

    private static let stateSourceA = """
        enum Mode { case on, off }
        final class Alpha {
            var mode: Mode = .on
            func flip() { switch mode { case .on: mode = .off; case .off: mode = .on } }
        }
        """

    private static let stateSourceB = """
        enum Light { case red, green }
        final class Lamp {
            var light: Light = .red
            func toggle() { switch light { case .red: light = .green; case .green: light = .red } }
        }
        """

    /// A fresh directory holding `source` in one file. Each test removes its own.
    private static func directory(holding source: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("background-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: directory.appendingPathComponent("Source.swift"), atomically: true, encoding: .utf8)
        return directory.path
    }

    private static func remove(_ paths: String...) {
        for path in paths { try? FileManager.default.removeItem(atPath: path) }
    }

    // MARK: - Off the main actor

    @Test("the entry-point scan runs off the main thread and publishes when it finishes")
    func entryPointScanRunsInBackground() async {
        let log = ScanStandIns.ThreadLog()
        let viewModel = DiagramViewModel(
            persistenceController: .init(inMemory: true),
            sequenceGenerator: ScanStandIns.RecordingSequenceGenerator(log: log)
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]

        viewModel.refreshEntryPoints()
        #expect(viewModel.availableEntryPoints.isEmpty, "the scan ran before refreshEntryPoints returned")
        await viewModel.entryPointsTask?.value

        #expect(log.entries == [false])
        #expect(viewModel.availableEntryPoints == ["Mock.run"])
    }

    @Test("the state-machine scan runs off the main thread")
    func stateMachineScanRunsInBackground() async {
        let log = ScanStandIns.ThreadLog()
        let viewModel = DiagramViewModel(
            persistenceController: .init(inMemory: true), stateGenerator: ScanStandIns.RecordingStateGenerator(log: log)
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]

        viewModel.refreshStateMachines()
        #expect(log.entries.isEmpty, "the scan ran before refreshStateMachines returned")
        await viewModel.stateMachinesTask?.value

        #expect(log.entries == [false])
    }

    // MARK: - Dropped results

    @Test("an entry-point result is dropped when the selection changed without a new scan")
    func entryPointsDroppedForChangedSelection() async throws {
        let pathA = try Self.directory(holding: Self.entrySourceA)
        let pathB = try Self.directory(holding: Self.entrySourceB)
        defer { Self.remove(pathA, pathB) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.availableEntryPoints = ["Earlier.list"]
        viewModel.selectedPaths = [pathA]
        viewModel.refreshEntryPoints()
        let scan = try #require(viewModel.entryPointsTask)

        viewModel.selectedPaths = [pathB]
        await scan.value

        #expect(viewModel.availableEntryPoints == ["Earlier.list"])
    }

    /// The selection is the scanned one again by the time the result arrives, so only the cancel
    /// can drop it. The stand-in lists `Mock.run` whether or not it was cancelled, as a real scan
    /// cancelled partway lists what it parsed before the cancel.
    @Test("a cancelled entry-point scan is dropped even when its selection is back")
    func cancelledEntryPointScanDropped() async throws {
        let viewModel = DiagramViewModel(
            persistenceController: .init(inMemory: true),
            sequenceGenerator: ScanStandIns.RecordingSequenceGenerator(log: ScanStandIns.ThreadLog())
        )
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.refreshEntryPoints()
        let scan = try #require(viewModel.entryPointsTask)

        viewModel.selectedPaths = []
        viewModel.refreshEntryPoints()
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        await scan.value

        #expect(viewModel.availableEntryPoints.isEmpty)
    }

    /// The cancel reaches the scan while it runs, so the generators stop parsing at the next file
    /// (`ParsingStack.parse`) rather than reading the whole replaced selection.
    @Test("a newer scan cancels the running one's work, not only its result")
    func cancelReachesRunningScan() async throws {
        let generator = ScanStandIns.GatedSequenceGenerator()
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true), sequenceGenerator: generator)
        viewModel.selectedPaths = ["/tmp/A.swift"]
        viewModel.refreshEntryPoints()
        let older = try #require(viewModel.entryPointsTask)
        await Task.detached { generator.waitUntilStarted() }.value

        viewModel.selectedPaths = ["/tmp/B.swift"]
        viewModel.refreshEntryPoints()
        generator.release.signal()
        await older.value

        #expect(generator.firstCallSawCancel)
        #expect(viewModel.availableEntryPoints != ["Gated.run"])
    }

    @Test("a newer entry-point scan's result replaces the one it cancelled")
    func newerEntryPointScanWins() async throws {
        let pathA = try Self.directory(holding: Self.entrySourceA)
        let pathB = try Self.directory(holding: Self.entrySourceB)
        defer { Self.remove(pathA, pathB) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = [pathA]
        viewModel.refreshEntryPoints()
        let older = try #require(viewModel.entryPointsTask)

        viewModel.selectedPaths = [pathB]
        viewModel.refreshEntryPoints()
        await older.value
        await viewModel.entryPointsTask?.value

        #expect(viewModel.availableEntryPoints == ["Beta.go"])
    }

    @Test("a dropped state-machine result leaves the list and the identifier alone")
    func stateMachinesDroppedForChangedSelection() async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA)
        let pathB = try Self.directory(holding: Self.stateSourceB)
        defer { Self.remove(pathA, pathB) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.stateIdentifier = "Gone.State"
        viewModel.selectedPaths = [pathA]
        viewModel.refreshStateMachines()
        let scan = try #require(viewModel.stateMachinesTask)

        viewModel.selectedPaths = [pathB]
        await scan.value

        #expect(viewModel.availableStateMachines.isEmpty)
        #expect(viewModel.stateIdentifier == "Gone.State")
    }

    @Test("a cancelled state-machine scan is dropped even when its selection is back")
    func cancelledStateMachineScanDropped() async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA)
        defer { Self.remove(pathA) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.stateIdentifier = "Gone.State"
        viewModel.selectedPaths = [pathA]
        viewModel.refreshStateMachines()
        let scan = try #require(viewModel.stateMachinesTask)

        viewModel.selectedPaths = []
        viewModel.refreshStateMachines()
        viewModel.selectedPaths = [pathA]
        await scan.value

        #expect(viewModel.availableStateMachines.isEmpty)
        #expect(viewModel.stateIdentifier == "Gone.State")
    }

    @Test("a kept state-machine result moves an unlisted identifier to the first machine")
    func keptStateMachineResultMovesIdentifier() async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA)
        defer { Self.remove(pathA) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.stateIdentifier = "Gone.State"
        viewModel.selectedPaths = [pathA]

        viewModel.refreshStateMachines()
        await viewModel.stateMachinesTask?.value

        #expect(viewModel.availableStateMachines.map(\.identifier) == ["Alpha.Mode"])
        #expect(viewModel.stateIdentifier == "Alpha.Mode")
    }

    // MARK: - Generation

    /// Leaving State Machine cancels its scan, whose late identifier change would restart the
    /// generation of the mode the user moved to. Both branches that leave it are checked: a mode
    /// with no scan, and one that starts its own.
    @Test("leaving State Machine stops its scan from moving the identifier",
          arguments: [DiagramMode.classDiagram, .sequenceDiagram])
    func leavingStateModeCancelsItsScan(destination: DiagramMode) async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA)
        defer { Self.remove(pathA) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .stateMachine
        viewModel.selectedPaths = [pathA]
        viewModel.refreshModeDerivedData()
        let scan = try #require(viewModel.stateMachinesTask)

        viewModel.diagramMode = destination
        viewModel.refreshModeDerivedData()
        await scan.value

        #expect(viewModel.stateIdentifier.isEmpty)
    }

    @Test("leaving Sequence Diagram cancels its scan", arguments: [DiagramMode.stateMachine, .classDiagram])
    func leavingSequenceModeCancelsItsScan(destination: DiagramMode) async throws {
        let viewModel = DiagramViewModel(
            persistenceController: .init(inMemory: true),
            sequenceGenerator: ScanStandIns.RecordingSequenceGenerator(log: ScanStandIns.ThreadLog())
        )
        viewModel.diagramMode = .sequenceDiagram
        viewModel.selectedPaths = ["/tmp/Foo.swift"]
        viewModel.refreshModeDerivedData()
        let scan = try #require(viewModel.entryPointsTask)

        viewModel.diagramMode = destination
        viewModel.refreshModeDerivedData()
        await scan.value

        #expect(viewModel.availableEntryPoints.isEmpty)
    }

    /// The scan outlasts the generation's 300 ms pause, which drew the identifier it was about to
    /// replace before the fix.
    @Test("a state diagram waits for the running scan and draws the machine it lists")
    func stateGenerationWaitsForScan() async throws {
        let generator = ScanStandIns.GatedStateGenerator()
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true), stateGenerator: generator)
        viewModel.diagramMode = .stateMachine
        viewModel.stateIdentifier = "Gone.State"
        viewModel.selectedPaths = ["/tmp/Foo.swift"]

        viewModel.refreshStateMachines()
        viewModel.generate()
        try await Task.sleep(for: .milliseconds(600))
        generator.release.signal()
        await viewModel.currentTask?.value

        #expect(generator.drawnIdentifiers == ["Alpha.Mode"])
    }

    // MARK: - Callers

    /// It scanned before restoring the selection, so its scan read the selection being replaced.
    @Test("reopening a sequence diagram scans the files it was saved with")
    func loadDiagramScansRestoredEntryPoints() async throws {
        let pathA = try Self.directory(holding: Self.entrySourceA)
        defer { Self.remove(pathA) }
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        let entity = DiagramEntity()
        entity.mode = DiagramMode.sequenceDiagram.rawValue
        entity.entryPoint = "Alpha.run"
        entity.paths = try JSONEncoder().encode([pathA])
        persistence.container.mainContext.insert(entity)

        viewModel.loadDiagram(entity)
        await viewModel.entryPointsTask?.value

        #expect(viewModel.availableEntryPoints == ["Alpha.run"])
    }

    @Test("reopening a state diagram scans the files it was saved with and keeps its machine")
    func loadDiagramScansRestoredStateMachines() async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA + "\n" + Self.stateSourceB)
        defer { Self.remove(pathA) }
        let persistence = PersistenceController(inMemory: true)
        let viewModel = DiagramViewModel(persistenceController: persistence)
        let entity = DiagramEntity()
        entity.mode = DiagramMode.stateMachine.rawValue
        entity.entryPoint = "Lamp.Light"
        entity.paths = try JSONEncoder().encode([pathA])
        persistence.container.mainContext.insert(entity)

        viewModel.loadDiagram(entity)
        await viewModel.stateMachinesTask?.value

        #expect(viewModel.availableStateMachines.map(\.identifier) == ["Alpha.Mode", "Lamp.Light"])
        #expect(viewModel.stateIdentifier == "Lamp.Light")
    }

    /// The suggestion's machine, listed by the scan that finishes after `apply` returns, is kept
    /// rather than replaced by the first one listed.
    @Test("a state-machine suggestion keeps its machine once the scan finishes")
    func suggestionKeepsItsMachine() async throws {
        let pathA = try Self.directory(holding: Self.stateSourceA + "\n" + Self.stateSourceB)
        defer { Self.remove(pathA) }
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = [pathA]
        let suggestion = DiagramSuggestion(
            icon: "", title: "Lamp", description: "",
            action: .stateMachine(identifier: "Lamp.Light"), requiresPro: false
        )

        SuggestionDispatcher.apply(suggestion, to: viewModel)
        await viewModel.stateMachinesTask?.value

        #expect(viewModel.stateIdentifier == "Lamp.Light")
    }
}
