import Foundation

/// Built-in themes for PlantUML diagrams
public enum Theme: Codable, Sendable {
    public static let preferred: [Theme] = [
        .amiga, .carbonGray, .cloudscapeDesign, .mars, .minty,
        .plain, .reddressDarkblue, .sketchy, .sketchyOutline, .toy
    ]

    case amiga, awsOrange, blackKnight, bluegray, blueprint
    case carbonGray, ceruleanOutline, cerulean, cloudscapeDesign, crtAmber
    case crtGreen, cyborgOutline, cyborg, hacker, lightgray
    case mars, materiaOutline, materia, metal, mimeograph
    case minty, plain, reddressDarkblue, reddressDarkgreen, reddressDarkorange
    case reddressDarkred, reddressLightblue, reddressLightgreen, reddressLightorange, reddressLightred
    case sandstone, silver, sketchyOutline, sketchy, spacelab
    case spacelabWhite, superheroOutline, superhero, toy, united, vibrant
    case __directive__(String)

    public var rawValue: String {
        switch self {
        case let .__directive__(name):
            return "\(name)"
        default:
            return String(describing: self).camelCaseToKebapCase()
        }
    }
}

private extension String {
    func processKebapCaseRegex(pattern: String) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: count)
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
