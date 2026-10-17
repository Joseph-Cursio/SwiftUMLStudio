import Foundation
import Synchronization
import Testing
@testable import SwiftUMLBridgeFramework

/// The lines an echo sink was handed.
private final class EchoedLines: Sendable {
    let lines = Mutex<[String]>([])
}

@Suite("BridgeLogger")
struct BridgeLoggerTests {

    @Test("BridgeLogger.shared is non-nil singleton")
    func sharedIsNonNil() {
        let logger = BridgeLogger.shared
        #expect(logger === BridgeLogger.shared)
    }

    @Test("info does not crash")
    func infoDoesNotCrash() {
        BridgeLogger.shared.info("test info message")
        #expect(Bool(true))
    }

    @Test("error does not crash")
    func errorDoesNotCrash() {
        BridgeLogger.shared.error("test error message")
        #expect(Bool(true))
    }

    @Test("warning does not crash")
    func warningDoesNotCrash() {
        BridgeLogger.shared.warning("test warning message")
        #expect(Bool(true))
    }

    @Test("debug does not crash")
    func debugDoesNotCrash() {
        BridgeLogger.shared.debug("test debug message")
        #expect(Bool(true))
    }

    @Test("multiple concurrent log calls do not crash")
    func multipleLogCallsDoNotCrash() {
        BridgeLogger.shared.info("message 1")
        BridgeLogger.shared.warning("message 2")
        BridgeLogger.shared.error("message 3")
        BridgeLogger.shared.debug("message 4")
        #expect(Bool(true))
    }

    /// `--verbose` hands every message to stderr through this (#138). Other tests log while this
    /// one runs, so it looks only for its own messages.
    @Test("echo(to:) hands each message to the sink with its level, until it is cleared")
    func echoesToSink() {
        let echoed = EchoedLines()
        let marker = UUID().uuidString
        BridgeLogger.shared.echo { line in echoed.lines.withLock { $0.append(line) } }
        BridgeLogger.shared.info("\(marker) info")
        BridgeLogger.shared.error("\(marker) error")
        BridgeLogger.shared.echo(to: nil)
        BridgeLogger.shared.info("\(marker) after")

        #expect(echoed.lines.withLock { $0 }.filter { $0.contains(marker) } == [
            "info: \(marker) info", "error: \(marker) error"
        ])
    }
}
