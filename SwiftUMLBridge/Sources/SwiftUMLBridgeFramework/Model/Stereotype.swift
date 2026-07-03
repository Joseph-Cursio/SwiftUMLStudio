import Foundation

/// Stereotypes for entity types
public struct Stereotypes: Codable, Sendable {
    public static var `default`: Stereotypes {
        Stereotypes(
            classStereotype: Stereotype.class,
            structStereotype: Stereotype.struct,
            extensionStereotype: Stereotype.extension,
            enumStereotype: Stereotype.enum,
            protocolStereotype: Stereotype.protocol
        )
    }

    public init(
        classStereotype: Stereotype? = nil,
        structStereotype: Stereotype? = nil,
        extensionStereotype: Stereotype? = nil,
        enumStereotype: Stereotype? = nil,
        protocolStereotype: Stereotype? = nil
    ) {
        self.class = classStereotype
        self.struct = structStereotype
        self.extension = extensionStereotype
        self.enum = enumStereotype
        self.protocol = protocolStereotype
    }

    public var `class`: Stereotype?
    public var `struct`: Stereotype?
    public var `extension`: Stereotype?
    public var `enum`: Stereotype?
    public var `protocol`: Stereotype?
}

/// Spotted character with background color and optional name for a stereotype
public struct Stereotype: Codable, Sendable {
    /// The stereotype label shown after the spot (e.g. `struct`), or `nil` for spot-only.
    public var name: String?
    /// The single spotted character and its background color.
    public var spot: Spot

    var plantuml: String {
        guard let name = name else {
            return "<< (\(spot.character), \(spot.color.rawValue)) >>"
        }
        return "<< (\(spot.character), \(spot.color.rawValue)) \(name) >>"
    }

    public static let `class` = Stereotype(
        spot: Spot(character: "C", color: .darkSeaGreen)
    )
    public static let `struct` = Stereotype(
        name: "struct", spot: Spot(character: "S", color: .skyBlue)
    )
    public static let `extension` = Stereotype(
        name: "extension", spot: Spot(character: "X", color: .orchid)
    )
    public static let `enum` = Stereotype(
        name: "enum", spot: Spot(character: "E", color: .lightSteelBlue)
    )
    public static let `protocol` = Stereotype(
        name: "protocol", spot: Spot(character: "P", color: .goldenRod)
    )
    public static let actor = Stereotype(
        name: "actor", spot: Spot(character: "A", color: .cadetBlue)
    )
}

/// Spotted character with background color
public struct Spot: Codable, Sendable {
    /// The single character drawn inside the stereotype spot (e.g. `C` for class).
    public var character: Character
    /// The spot's background color.
    public var color: Color
}

extension Character: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard !string.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Decoder expected a Character but found an empty string."
            )
        }
        guard string.count == 1 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Decoder expected a Character but found a string: \(string)"
            )
        }
        self = string[string.startIndex]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self))
    }
}
