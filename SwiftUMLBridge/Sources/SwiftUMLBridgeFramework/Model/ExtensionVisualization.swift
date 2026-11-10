/// Options which and how extensions shall be considered for class diagram generation
public enum ExtensionVisualization: String, Codable, Sendable {
    case all
    case merged
    case none

    static func from(_ showExtensions: Bool) -> Self {
        showExtensions ? .all : .none
    }

    public static var `default`: Self { .all }
}

extension Optional where Wrapped == ExtensionVisualization {
    var safelyUnwrap: ExtensionVisualization {
        self ?? ExtensionVisualization.default
    }
}
