//
//  ScanStandIns.swift
//  SwiftUMLStudioTests
//
//  Generators that stand in for the real scans in BackgroundScanTests.
//

import Foundation
import SwiftUMLBridgeFramework
import Synchronization

/// Generators that stand in for the real scans in `BackgroundScanTests`, and what they record.
enum ScanStandIns {
    /// How long a gated stand-in waits before going on without its signal. A scan that wrongly runs on
    /// the main actor blocks the test that would signal it; the timeout turns that deadlock into a
    /// failed expectation instead of a hung run.
    static let gateTimeout = DispatchTimeInterval.seconds(10)

    /// Which threads a scan ran on, recorded by the stand-in generators below.
    final class ThreadLog: Sendable {
        private let onMainThread = Mutex<[Bool]>([])

        var entries: [Bool] { onMainThread.withLock { $0 } }

        func record() {
            let isMain = Thread.isMainThread
            onMainThread.withLock { $0.append(isMain) }
        }
    }

    struct RecordingSequenceGenerator: SequenceDiagramGenerating {
        let log: ThreadLog

        func findEntryPoints(for _: [String]) -> [String] {
            log.record()
            return ["Mock.run"]
        }

        func generateScript(
            for _: [String], entryType _: String, entryMethod _: String, depth _: Int, with _: Configuration
        ) -> SequenceScript {
            .empty
        }
    }

    struct RecordingStateGenerator: StateMachineGenerating {
        let log: ThreadLog

        func findCandidates(for _: [String]) -> [StateMachineModel] {
            log.record()
            return []
        }

        func generateScript(for _: [String], stateIdentifier _: String, with _: Configuration) -> StateScript {
            .empty
        }
    }

    /// A state-machine scan that lists one machine, `Alpha.Mode`, once `release` is signalled (or the
    /// gate times out), and records the identifiers it is asked to draw.
    final class GatedStateGenerator: StateMachineGenerating {
        let release = DispatchSemaphore(value: 0)
        private let drawn = Mutex<[String]>([])

        var drawnIdentifiers: [String] { drawn.withLock { $0 } }

        func findCandidates(for _: [String]) -> [StateMachineModel] {
            _ = release.wait(timeout: .now() + ScanStandIns.gateTimeout)
            return [StateMachineModel(hostType: "Alpha", enumType: "Mode", states: [], transitions: [])]
        }

        func generateScript(for _: [String], stateIdentifier: String, with _: Configuration) -> StateScript {
            drawn.withLock { $0.append(stateIdentifier) }
            return .empty
        }
    }

    /// An entry-point scan whose first call waits for `release` (or the gate timeout) after saying it
    /// `started`, then records whether its task was cancelled by then. Later calls return at once.
    final class GatedSequenceGenerator: SequenceDiagramGenerating {
        private let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let calls = Mutex(0)
        private let cancelled = Mutex(false)

        var firstCallSawCancel: Bool { cancelled.withLock { $0 } }

        /// Blocks until the first call has started. Call it off the main actor.
        func waitUntilStarted() {
            _ = started.wait(timeout: .now() + ScanStandIns.gateTimeout)
        }

        func findEntryPoints(for _: [String]) -> [String] {
            let call = calls.withLock { count in
                count += 1
                return count
            }
            guard call == 1 else { return [] }
            started.signal()
            _ = release.wait(timeout: .now() + ScanStandIns.gateTimeout)
            let isCancelled = Task.isCancelled
            cancelled.withLock { $0 = isCancelled }
            return ["Gated.run"]
        }

        func generateScript(
            for _: [String], entryType _: String, entryMethod _: String, depth _: Int, with _: Configuration
        ) -> SequenceScript {
            .empty
        }
    }
}
