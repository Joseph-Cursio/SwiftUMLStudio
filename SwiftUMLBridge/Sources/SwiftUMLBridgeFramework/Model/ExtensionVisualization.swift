import Foundation

/// Options which and how extensions shall be considered for class diagram generation
public enum ExtensionVisualization: String, Codable, Sendable {
    case all
    case merged
    /// Written `none` in a config file. Not named `none` in Swift, where `.none` beside an
    /// `ExtensionVisualization?` means nil, the default, which draws every extension.
    case hidden = "none"

    static func from(_ showExtensions: Bool) -> ExtensionVisualization {
        showExtensions ? .all : .hidden
    }

    public static var `default`: ExtensionVisualization { .all }
}

extension Optional where Wrapped == ExtensionVisualization {
    var safelyUnwrap: ExtensionVisualization {
        self ?? ExtensionVisualization.default
    }
}
