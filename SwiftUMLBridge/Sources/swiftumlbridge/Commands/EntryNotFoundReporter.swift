import Foundation

/// Says on stderr when `--entry` came to no method with a body, so the sequence or activity
/// diagram is empty for that reason, and not because the method calls or does nothing (#239). The
/// diagram is still written and the exit status is the same, as before.
enum EntryNotFoundReporter {
    /// The line to print for `entry` as typed, or `nil` when it was found.
    static func warning(entry: String, found: Bool) -> String? {
        guard !found else { return nil }
        return "warning: --entry \(entry) came to no method with a body in the given sources, "
            + "so the diagram is empty\n"
    }

    /// Writes the warning for `entry`, if any, to `report`, stderr by default.
    static func report(
        entry: String,
        found: Bool,
        to report: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) {
        if let warning = warning(entry: entry, found: found) { report(warning) }
    }
}
