import Foundation

/// Built-in themes for PlantUML diagrams
public enum Theme: Codable, Sendable {
    public static let preferred: [Self] = [
        .amiga, .carbonGray, .cloudscapeDesign, .mars, .minty,
        .plain, .reddressDarkblue, .sketchy, .sketchyOutline, .toy,
    ]

    case amiga, awsOrange, blackKnight, bluegray, blueprint
    case carbonGray, ceruleanOutline, cerulean, cloudscapeDesign, crtAmber
    case crtGreen, cyborgOutline, cyborg, hacker, lightgray
    case mars, materiaOutline, materia, metal, mimeograph
    case minty, plain, reddressDarkblue, reddressDarkgreen, reddressDarkorange
    case reddressDarkred, reddressLightblue, reddressLightgreen, reddressLightorange, reddressLightred
    case sandstone, silver, sketchyOutline, sketchy, spacelab
    case spacelabWhite, superheroOutline, superhero, toy, united, vibrant
    case directive(String)

    /// Every case above but `directive`, which carries a value and so keeps `Theme` from being
    /// `CaseIterable`. A case added above goes here too; `ThemeTests` pins the count.
    static let builtIn: [Self] = [
        .amiga, .awsOrange, .blackKnight, .bluegray, .blueprint,
        .carbonGray, .ceruleanOutline, .cerulean, .cloudscapeDesign, .crtAmber,
        .crtGreen, .cyborgOutline, .cyborg, .hacker, .lightgray,
        .mars, .materiaOutline, .materia, .metal, .mimeograph,
        .minty, .plain, .reddressDarkblue, .reddressDarkgreen, .reddressDarkorange,
        .reddressDarkred, .reddressLightblue, .reddressLightgreen, .reddressLightorange, .reddressLightred,
        .sandstone, .silver, .sketchyOutline, .sketchy, .spacelab,
        .spacelabWhite, .superheroOutline, .superhero, .toy, .united, .vibrant,
    ]

    /// The theme a config file's `theme:` value names: the built-in theme whose case name it
    /// is, so `carbonGray` writes PlantUML's `carbon-gray`, or else the value itself, written
    /// after `!theme` as it is, so `hacker from https://example.com/themes` takes a hosted
    /// theme. A case name matches only as written, in camelCase.
    init(configValue value: String) {
        self = Self.builtIn.first { String(describing: $0) == value } ?? .directive(value)
    }

    public var rawValue: String {
        switch self {
        case let .directive(name):
            return "\(name)"

        default:
            return String(describing: self).camelCaseToKebapCase()
        }
    }
}

private extension String {
    func processKebapCaseRegex(pattern: String) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(startIndex..., in: self)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1-$2")
    }
}

// Internal rather than private so a test can call it directly.
extension String {
    func camelCaseToKebapCase() -> String {
        let acronymPattern = "([A-Z]+)([A-Z][a-z]|[0-9])"
        let normalPattern = "([a-z0-9])([A-Z])"
        return processKebapCaseRegex(pattern: acronymPattern)?
            .processKebapCaseRegex(pattern: normalPattern)?.lowercased() ?? lowercased()
    }
}
