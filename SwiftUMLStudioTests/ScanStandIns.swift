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
    /// How long a gated stand-in waits before going on without its signal or cancel. A scan that
    /// wrongly runs on the main actor blocks the code that would send it; the timeout turns that
    /// deadlock into a failed expectation instead of a hung run.
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

    /// An entry-point scan whose first call runs `onStart` on the main queue, then waits (up to
    /// `gateTimeout`) for its task to be cancelled and records whether it was. Later calls return at
    /// once.
    ///
    /// The scan sets the newer scan off itself, rather than signalling the test to. The test, woken
    /// while this scan held a cooperative thread, could need that thread to resume; on CI's few
    /// cores, and on a one-thread pool (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`), it waited out the
    /// gate. The main queue is not part of the pool.
    final class CancelAwaitingSequenceGenerator: SequenceDiagramGenerating {
        private let onStart = Mutex<(@Sendable @MainActor () -> Void)?>(nil)
        private let calls = Mutex(0)
        private let cancelled = Mutex(false)

        var firstCallSawCancel: Bool { cancelled.withLock { $0 } }

        /// Sets what the first call runs on the main queue once it has started.
        func whenStarted(_ action: @escaping @Sendable @MainActor () -> Void) {
            onStart.withLock { $0 = action }
        }

        func findEntryPoints(for _: [String]) -> [String] {
            let call = calls.withLock { count in
                count += 1
                return count
            }
            guard call == 1 else { return [] }
            if let action = onStart.withLock({ $0 }) {
                DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
            }
            let deadline = DispatchTime.now() + ScanStandIns.gateTimeout
            while !Task.isCancelled, DispatchTime.now() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
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
