import Foundation

/// Concurrency path: an `actor` whose `state: TaskState` is driven by an
/// async run loop. Mirrors common task / job-runner patterns.
public actor AsyncTaskActor {
    public enum TaskState {
        case pending
        case running
        case succeeded
        case failed
    }

    public private(set) var state: TaskState = .pending

    public func run() async {
        switch self.state {
        case .pending:
            self.state = .running
        case .running:
            self.state = .succeeded
        case .succeeded, .failed:
            break
        }
    }

    public func fail() {
        switch self.state {
        case .running:
            self.state = .failed
        case .pending, .succeeded, .failed:
            break
        }
    }
}
