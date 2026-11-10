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
