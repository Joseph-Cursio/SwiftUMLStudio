//
//  StateIdentifierRestoreTests.swift
//  SwiftUMLStudioTests
//
//  A saved state diagram reopens on the machine it named.
//

import Foundation
import SwiftUMLBridgeFramework
import Testing
@testable import SwiftUMLStudio

/// Since #123 every name is read as Swift reads it, so `` class `Lamp` `` lists its machine as
/// `Lamp.Light`. A state diagram saved before that stored `` `Lamp`.Light ``, which no candidate
/// matches exactly any more; it must still reopen on that machine, not on the first one listed.
@Suite("Restoring a saved state machine") @MainActor
struct StateIdentifierRestoreTests {

    private static let source = """
        enum Mode { case on, off }
        final class Alpha {
            var mode: Mode = .on
            func flip() { switch mode { case .on: mode = .off; case .off: mode = .on } }
        }
        enum Light { case red, green }
        final class `Lamp` {
            var light: Light = .red
            func toggle() { switch light { case .red: light = .green; case .green: light = .red } }
        }
        """

    @Test("an identifier saved with needless backticks selects the machine it named",
          arguments: ["`Lamp`.Light", "Lamp.Light"])
    func savedIdentifierSelectsItsMachine(saved: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.source.write(
            to: directory.appendingPathComponent("Machines.swift"), atomically: true, encoding: .utf8
        )

        let viewModel = DiagramViewModel()
        viewModel.selectedPaths = [directory.path]
        viewModel.stateIdentifier = saved
        viewModel.refreshStateMachines()

        #expect(viewModel.availableStateMachines.map(\.identifier) == ["Alpha.Mode", "Lamp.Light"])
        #expect(viewModel.stateIdentifier == "Lamp.Light")
    }
}
