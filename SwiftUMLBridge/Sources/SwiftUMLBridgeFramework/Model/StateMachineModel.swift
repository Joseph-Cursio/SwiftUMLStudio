import Foundation

/// A single state in a state machine (one enum case).
public struct StateMachineState: Sendable, Hashable {
    public let name: String
    public let isInitial: Bool
    public let isFinal: Bool

    public init(name: String, isInitial: Bool = false, isFinal: Bool = false) {
        self.name = name
        self.isInitial = isInitial
        self.isFinal = isFinal
    }
}

/// A transition between two states, triggered by a method on the host type.
public struct StateTransition: Sendable, Hashable {
    public let from: String
    public let toState: String
    public let trigger: String?
    public let guardText: String?

    public init(from: String, toState: String, trigger: String? = nil, guardText: String? = nil) {
        self.from = from
        self.toState = toState
        self.trigger = trigger
        self.guardText = guardText
    }
}

/// A candidate state machine detected in Swift source.
///
/// Identifies a `(hostType, enumType)` pair where an enum is used to track
/// state on a class/struct/actor and transitions happen via `self.prop = .case`
/// assignments inside `switch` branches.
public struct StateMachineModel: Sendable, Hashable {
    public let hostType: String
    public let enumType: String
    public let states: [StateMachineState]
    public let transitions: [StateTransition]

    public init(
        hostType: String,
        enumType: String,
        states: [StateMachineState],
        transitions: [StateTransition]
    ) {
        self.hostType = hostType
        self.enumType = enumType
        self.states = states
        self.transitions = transitions
    }

    /// Display identifier for the picker: `"HostType.EnumType"`.
    public var identifier: String { "\(hostType).\(enumType)" }
}
