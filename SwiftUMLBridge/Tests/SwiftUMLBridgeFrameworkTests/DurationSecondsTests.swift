import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// The conversion the three timed stages share.
///
/// They each measured with two `Date` reads before this, so an elapsed time could be corrupted by a
/// clock step and the log line would report a number that never happened. `ContinuousClock` cannot
/// step; this is the arithmetic that turns its `Duration` into the seconds the logger prints.
@Suite("Duration in seconds")
struct DurationSecondsTests {

    @Test("a whole number of seconds converts exactly")
    func wholeSecondsAreExact() {
        #expect(Duration.seconds(3).seconds == 3.0)
        #expect(Duration.seconds(0).seconds == 0.0)
    }

    /// Parsing one file is routinely sub-second, so dropping the attosecond component would report
    /// every one of those stages as `0.0`.
    @Test("the fractional part survives")
    func fractionsSurvive() {
        #expect(Duration.milliseconds(1500).seconds == 1.5)
        #expect(Duration.milliseconds(4).seconds == 0.004)
    }

    /// Monotone in the duration — the only thing a reader does with two of these numbers is compare
    /// them.
    @Test("longer durations convert to larger numbers", arguments: [
        (1, 2), (99, 100), (1_000, 60_000),
    ])
    func conversionIsMonotone(shorter: Int, longer: Int) {
        #expect(Duration.milliseconds(shorter).seconds < Duration.milliseconds(longer).seconds)
    }
}
