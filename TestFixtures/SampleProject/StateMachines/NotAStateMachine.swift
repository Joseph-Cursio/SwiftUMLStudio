import Foundation

/// Negative case: a discriminated union with associated values that the
/// detector must reject. There is no enum-typed stored property and no
/// `self.x = .case` assignment anywhere; the enum is just a return /
/// parameter type for utility functions. The state-machine detector should
/// produce zero candidates for this file.
public enum LoadResult<Value> {
    case success(Value)
    case failure(Error)
    case retrying(attempt: Int)
}

public struct ResultParser {
    public init() {}

    public func describe<Value>(_ result: LoadResult<Value>) -> String {
        switch result {
        case .success:
            return "ok"
        case .failure(let error):
            return "failed: \(error)"
        case .retrying(let attempt):
            return "retrying (attempt \(attempt))"
        }
    }

    public func combine<Value>(_ lhs: LoadResult<Value>, _ rhs: LoadResult<Value>) -> LoadResult<Value> {
        switch (lhs, rhs) {
        case (.success, _):
            return lhs
        case (_, .success):
            return rhs
        default:
            return lhs
        }
    }
}
