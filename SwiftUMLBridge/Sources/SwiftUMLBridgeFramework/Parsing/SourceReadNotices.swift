import Foundation
import Synchronization

/// What the parsers were not given as written, for the CLI to print and an app to show: so far,
/// a chain of `[` cut short so that its parse ends (#148). Each notice is also logged as a warning.
///
/// The notices are kept for the whole process, as the parse that finds one does not know which
/// diagram it is for. A file read by several passes gives one notice.
public enum SourceReadNotices {
    private static let pending = Mutex<[String]>([])

    static func record(_ notice: String) {
        let isNew = pending.withLock { notices in
            guard !notices.contains(notice) else { return false }
            notices.append(notice)
            return true
        }
        if isNew { BridgeLogger.shared.warning(notice) }
    }

    /// The notices recorded since the last call, in the order they were found, and clears them.
    public static func drain() -> [String] {
        pending.withLock { notices in
            defer { notices.removeAll() }
            return notices
        }
    }
}
