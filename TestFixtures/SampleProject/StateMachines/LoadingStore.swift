import Combine
import Foundation

/// Property-wrapper path: a `@Published` enum inside an `ObservableObject`,
/// driven by an async loader that self-assigns the next state in each branch
/// of a switch.
public final class LoadingStore: ObservableObject {
    public enum LoadState {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published public var state: LoadState = .idle

    public func reload() async {
        switch self.state {
        case .idle, .failed:
            self.state = .loading
        case .loading:
            self.state = .loaded
        case .loaded:
            self.state = .idle
        }
    }

    public func report(error: Error) {
        switch self.state {
        case .loading:
            self.state = .failed
        case .idle, .loaded, .failed:
            break
        }
    }
}
