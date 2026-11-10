import Foundation

extension Duration {
    /// This duration as seconds, for the elapsed times the logger prints.
    ///
    /// A monotonic clock hands back a `Duration`; the log lines want a number. Written once so the
    /// three call sites that time a stage cannot drift apart on the arithmetic.
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
