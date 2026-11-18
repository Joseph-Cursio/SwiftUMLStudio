import Synchronization

/// The notices one run's parses found, once each, in the order they were found. Bind it as
/// `SourceReadNotices.collector` around the run.
public final class SourceReadNoticeCollector: Sendable {
    private let collected = Mutex<[String]>([])

    public init() {
        // Starts empty: the run's parses fill it through `SourceReadNotices.record`.
    }

    /// What the run has found so far.
    public var notices: [String] { collected.withLock { $0 } }

    /// Adds `notice` unless it is already here, and says whether it was new.
    func add(_ notice: String) -> Bool {
        collected.withLock { notices in
            guard !notices.contains(notice) else { return false }
            notices.append(notice)
            return true
        }
    }
}

/// What the parsers were not given as written, for the CLI to print and an app to show: so far,
/// a chain of `[` cut short so that its parse ends (#148). Each notice is also logged as a warning.
///
/// A run that binds a `collector` gets the notices its own parses find, and no other run's: Studio
/// binds one for each generation, so two windows generating at once each show their own. Without
/// one, the notices are kept for the whole process until `drain()`, which suits the CLI: it makes
/// one diagram a process. A file read by several passes gives one notice either way.
public enum SourceReadNotices {
    private static let pending = Mutex<[String]>([])

    /// Where the notices the current task's parses find go, instead of the process-wide list.
    /// `ParsingStack.run` binds it on its parsing thread too. A detached task takes none from the
    /// task that starts it, so that task must bind it inside.
    @TaskLocal public static var collector: SourceReadNoticeCollector?

    static func record(_ notice: String) {
        let isNew: Bool
        if let collector {
            isNew = collector.add(notice)
        } else {
            isNew = pending.withLock { notices in
                guard !notices.contains(notice) else { return false }
                notices.append(notice)
                return true
            }
        }
        if isNew { BridgeLogger.shared.warning(notice) }
    }

    /// The notices recorded with no `collector` bound since the last call, in the order they were
    /// found, and clears them.
    public static func drain() -> [String] {
        pending.withLock { notices in
            defer { notices.removeAll() }
            return notices
        }
    }
}
