import Foundation

/// Represents a single call relationship between a caller method and a callee method.
public struct CallEdge: Sendable, Hashable {
    /// The type that contains the calling method.
    public let callerType: String

    /// The name of the calling method.
    public let callerMethod: String

    /// The type of the callee, or nil when the callee is unresolved.
    public let calleeType: String?

    /// The name of the called method.
    public let calleeMethod: String

    /// Whether the call is wrapped in an `await` expression.
    public let isAsync: Bool

    /// Whether the callee could not be statically resolved (variable receiver, closure, etc.)
    public let isUnresolved: Bool

    /// The body the call is written in (`CallBody.identifier`), which tells it from the other
    /// bodies filed under `callerType.callerMethod` (#235). `nil` for an edge made with `init`,
    /// which is followed by name alone.
    var callerBody: String?

    /// The function local to a body that the call names, when one is declared where the call can
    /// see it: Swift calls it, not the member of that name.
    var calleeBody: String?

    /// The type local to a body that the callee is a member of, when the call is to `self` in
    /// such a type's member, or names such a type where it is declared.
    var calleeLocalType: String?

    /// The call's argument labels, `_` for none, which tell the overload it calls; `nil` when
    /// they cannot, as with a trailing closure.
    var argumentLabels: [String]?

    public init(
        callerType: String,
        callerMethod: String,
        calleeType: String?,
        calleeMethod: String,
        isAsync: Bool,
        isUnresolved: Bool
    ) {
        self.callerType = callerType
        self.callerMethod = callerMethod
        self.calleeType = calleeType
        self.calleeMethod = calleeMethod
        self.isAsync = isAsync
        self.isUnresolved = isUnresolved
    }
}
