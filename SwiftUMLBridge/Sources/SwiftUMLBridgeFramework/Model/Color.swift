import Foundation

/// Colors supported by PlantUML (HTML color names, matched case-insensitively by PlantUML)
public enum Color: String, CaseIterable, Codable, Sendable {
    case aliceBlue, antiqueWhite, aqua, aquamarine, azure, beige, bisque, black
    case blanchedAlmond, blue, blueViolet, brown, burlyWood, cadetBlue, chartreuse, chocolate
    case coral, cornflowerBlue, cornsilk, crimson, cyan, darkBlue, darkCyan, darkGoldenRod
    case darkGray, darkGreen, darkGrey, darkKhaki, darkMagenta, darkOliveGreen, darkOrchid, darkRed
    case darkSalmon, darkSeaGreen, darkSlateBlue, darkSlateGray, darkSlateGrey, darkTurquoise, darkViolet, darkOrange
    case deepPink, deepSkyBlue, dimGray, dimGrey, dodgerBlue, fireBrick, floralWhite, forestGreen
    case fuchsia, gainsboro, ghostWhite, gold, goldenRod, gray, green, greenYellow
    case grey, honeyDew, hotPink, indianRed, indigo, ivory, khaki, lavender
    case lavenderBlush, lawnGreen, lemonChiffon, lightBlue, lightCoral, lightCyan, lightGoldenRodYellow, lightGray
    case lightGreen, lightGrey, lightPink, lightSalmon, lightSeaGreen, lightSkyBlue, lightSlateGray, lightSlateGrey
    case lightSteelBlue, lightYellow, lime, limeGreen, linen, magenta, maroon, mediumAquaMarine
    case mediumBlue, mediumOrchid, mediumPurple, mediumSeaGreen
    case mediumSlateBlue, mediumSpringGreen, mediumTurquoise, mediumVioletRed
    case midnightBlue, mintCream, mistyRose, moccasin, navajoWhite, navy, oldLace, olive
    case oliveDrab, orange, orangeRed, orchid, paleGoldenRod, paleGreen, paleTurquoise, paleVioletRed
    case papayaWhip, peachPuff, peru, pink, plum, powderBlue, purple, red
    case rosyBrown, royalBlue, saddleBrown, salmon, sandyBrown, seaGreen, seaShell, sienna
    case silver, skyBlue, slateBlue, slateGray, slateGrey, snow, springGreen, steelBlue
    case tan, teal, thistle, tomato, turquoise, violet, wheat, white
    case whiteSmoke, yellow, yellowGreen
}

extension Color {
    /// Reads a colour name in any case: `DarkGray`, `darkgray` and `darkGray` are all `.darkGray`.
    /// PlantUML matches HTML colour names case-insensitively, the reference writes them in
    /// PascalCase, and SwiftPlantUML's cases were PascalCase (#138). No two cases are equal when
    /// case is ignored. A diagram writes the case name, however the file spelt it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let color = Color.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame })
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "'\(name)' is not a colour name this tool knows"
            )
        }
        self = color
    }
}
