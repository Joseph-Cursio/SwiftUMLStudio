import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

/// Prints each of `SourceReadNotices` as a warning on stderr: a chain of `[` cut short so that
/// its parse ends is drawn without the brackets past the cut, and nothing else would say so (#148).
enum SourceReadNoticeReporter {
    /// The warning lines for `notices`, one each, or `""` when there are none.
    static func warnings(for notices: [String]) -> String {
        notices.map { "warning: \($0)\n" }.joined()
    }

    /// Drains `SourceReadNotices` and writes their warnings to `report`, stderr by default.
    static func report(to report: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }) {
        let text = warnings(for: SourceReadNotices.drain())
        if !text.isEmpty { report(text) }
    }
}
