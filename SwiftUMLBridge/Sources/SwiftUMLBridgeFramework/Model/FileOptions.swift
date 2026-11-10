/// Options which files shall be considered for class diagram generation
public struct FileOptions: Codable, Sendable, CustomStringConvertible {
    public init(include: [String]? = [], exclude: [String]? = []) {
        self.include = include
        self.exclude = exclude
    }

    public var include: [String]? = []
    public var exclude: [String]? = []

    public var description: String {
        let includeArray = include ?? []
        let excludeArray = exclude ?? []
        if includeArray.isEmpty, excludeArray.isEmpty {
            return "no values"
        }
        if includeArray.isEmpty {
            return "exclude: \(excludeArray.joined(separator: ", "))"
        }
        if excludeArray.isEmpty {
            return "include: \(includeArray.joined(separator: ", "))"
        }
        let includeStr = includeArray.joined(separator: ", ")
        let excludeStr = excludeArray.joined(separator: ", ")
        return "include: \(includeStr) && exclude: \(excludeStr)"
    }
}
