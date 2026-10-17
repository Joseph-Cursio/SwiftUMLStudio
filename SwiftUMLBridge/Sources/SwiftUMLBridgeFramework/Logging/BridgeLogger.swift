import Foundation
import os.log
import Synchronization

/// Singleton logger for SwiftUMLBridge using os.Logger
public final class BridgeLogger: Sendable {
    public static let shared: BridgeLogger = BridgeLogger()

    private let logger = Logger(subsystem: "name.JosephCursio.SwiftUMLBridge", category: "SwiftUMLBridge")

    /// Where each message also goes, as `info: <message>`: the CLI's `--verbose` sends them to
    /// stderr (#138). `nil` until `echo(to:)` sets one.
    private let sink = Mutex<(@Sendable (String) -> Void)?>(nil)

    private init() {}

    /// Also hands every message from here on to `sink`, prefixed with its level; `nil` stops.
    public func echo(to sink: (@Sendable (String) -> Void)?) {
        self.sink.withLock { $0 = sink }
    }

    private func echo(_ level: String, _ message: String) {
        sink.withLock { $0 }?("\(level): \(message)")
    }

    public func error(_ message: String, _ file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.error("\(message, privacy: .public)")
        echo("error", message)
    }

    public func warning(
        _ message: String,
        _ file: String = #file,
        _ function: String = #function,
        _ line: Int = #line
    ) {
        logger.warning("\(message, privacy: .public)")
        echo("warning", message)
    }

    public func info(_ message: String, _ file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.info("\(message, privacy: .public)")
        echo("info", message)
    }

    public func debug(_ message: String, _ file: String = #file, _ function: String = #function, _ line: Int = #line) {
        logger.debug("\(message, privacy: .public)")
        echo("debug", message)
    }
}
