import Foundation

/// What went wrong, in words, for the CLI's `Error:` line and any other reader of
/// `localizedDescription`, rather than the case dumped as Swift wrote it (#282).
extension SPMPackageReader.ReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .swiftToolFailed(exitStatus, stderr):
            let said = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`swift package` exited with status \(exitStatus)" + (said.isEmpty ? "" : ": \(said)")

        case .malformedJSON(let reason):
            return "could not read the output of `swift package describe` (\(reason))"

        case .timedOut(let seconds):
            return "`swift package` was stopped after \(String(format: "%g", seconds)) seconds without finishing"
        }
    }
}
