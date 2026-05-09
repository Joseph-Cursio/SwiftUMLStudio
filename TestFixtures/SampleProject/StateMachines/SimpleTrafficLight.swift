import Foundation

/// Canonical positive case for the state-machine detector: a class with a
/// stored `var` of an enum type and a method that switches on it,
/// self-assigning the next case in each branch.
public final class SimpleTrafficLight {
    public enum Phase {
        case red
        case green
        case yellow
    }

    public private(set) var phase: Phase = .red

    public func advance() {
        switch self.phase {
        case .red:
            self.phase = .green
        case .green:
            self.phase = .yellow
        case .yellow:
            self.phase = .red
        }
    }
}
