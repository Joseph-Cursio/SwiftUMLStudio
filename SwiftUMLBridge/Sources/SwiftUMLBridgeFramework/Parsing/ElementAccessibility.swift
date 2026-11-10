import Foundation

// Parallel List Drift pairs this with the app's `AccessLevel` enum, but this maps SourceKit's
// own accessibility keys (raw values `source.lang.swift.accessibility.*`) — a distinct layer.
// swiftprojectlint:disable:next parallel-list-drift
internal enum ElementAccessibility: String, RawRepresentable, Comparable, Codable, UnknownCaseRepresentable {
    internal static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    case open = "source.lang.swift.accessibility.open"
    case `public` = "source.lang.swift.accessibility.public"
    case package = "source.lang.swift.accessibility.package"
    case `internal` = "source.lang.swift.accessibility.internal"
    case `private` = "source.lang.swift.accessibility.private"
    case `fileprivate` = "source.lang.swift.accessibility.fileprivate"
    case other

    private var value: Int {
        switch self {
        case .open: return 7
        case .public: return 6
        case .package: return 5
        case .internal: return 4
        case .private: return 3
        case .fileprivate: return 2
        case .other: return 1
        }
    }

    internal init?(orig: AccessLevel) {
        switch orig {
        case .open: self.init(rawValue: "source.lang.swift.accessibility.open")
        case .public: self.init(rawValue: "source.lang.swift.accessibility.public")
        case .package: self.init(rawValue: "source.lang.swift.accessibility.package")
        case .internal: self.init(rawValue: "source.lang.swift.accessibility.internal")
        case .private: self.init(rawValue: "source.lang.swift.accessibility.private")
        case .fileprivate: self.init(rawValue: "source.lang.swift.accessibility.fileprivate")
        }
    }

    static let unknownCase: ElementAccessibility = .other
}
