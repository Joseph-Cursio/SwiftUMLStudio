import Foundation

/// Swift type representing an AST element (analogue to SourceKitten's Structure)
internal class SyntaxStructure: NSObject, Codable, @unchecked Sendable {
    internal init(
        accessibility: ElementAccessibility? = nil,
        attribute: String? = nil,
        attributes: [SyntaxStructure]? = nil,
        elements: [SyntaxStructure]? = nil,
        inheritedTypes: [SyntaxStructure]? = nil,
        kind: ElementKind? = nil,
        name: String? = nil,
        runtimename: String? = nil,
        substructure: [SyntaxStructure]? = nil,
        typename: String? = nil
    ) {
        self.accessibility = accessibility
        self.attribute = attribute
        self.attributes = attributes
        self.elements = elements
        self.inheritedTypes = inheritedTypes
        self.kind = kind
        self.name = name
        self.runtimename = runtimename
        self.substructure = substructure
        self.typename = typename
    }

    /// access level
    internal let accessibility: ElementAccessibility?
    internal let attribute: String?
    internal let attributes: [SyntaxStructure]?
    private let elements: [SyntaxStructure]?
    /// inheritedTypes (e.g. superclass)
    internal let inheritedTypes: [SyntaxStructure]?
    /// declaration kind
    internal let kind: ElementKind?
    /// name
    internal let name: String?
    /// runtime name
    private let runtimename: String?
    /// sub elements (e.g. variables and methods of a class/struct)
    internal var substructure: [SyntaxStructure]?
    /// typename
    internal let typename: String?

    internal var memberSuffix: String?

    internal var parent: SyntaxStructure?

    private enum CodingKeys: String, CodingKey {
        case accessibility = "key.accessibility"
        case attribute = "key.attribute"
        case attributes = "key.attributes"
        case elements = "key.elements"
        case inheritedTypes = "key.inheritedtypes"
        case kind = "key.kind"
        case name = "key.name"
        case runtimename = "key.runtime_name"
        case substructure = "key.substructure"
        case typename = "key.typename"
    }

    internal func find(_ type: ElementKind = .struct, named searchName: String) -> SyntaxStructure? {
        if name == searchName, kind == type {
            return self
        } else {
            guard let subs = substructure else { return nil }
            for sub in subs {
                if let found = sub.find(type, named: searchName) {
                    return found
                }
            }
        }
        return nil
    }
}

protocol UnknownCaseRepresentable: RawRepresentable, CaseIterable where RawValue: Equatable {
    static var unknownCase: Self { get }
}

extension UnknownCaseRepresentable {
    public init(rawValue: RawValue) {
        let value = Self.allCases.first(where: { $0.rawValue == rawValue })
        self = value ?? Self.unknownCase
    }
}

internal enum ElementAccessibility: String, RawRepresentable, Comparable {
    internal static func < (lhs: ElementAccessibility, rhs: ElementAccessibility) -> Bool {
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
}

extension ElementAccessibility: Codable {}

extension ElementAccessibility: UnknownCaseRepresentable {
    static let unknownCase: ElementAccessibility = .other
}

// https://github.com/jpsim/SourceKitten/blob/master/Source/SourceKittenFramework/SwiftDeclarationKind.swift
/// Analogous to SourceKittenFramework's `SwiftDeclarationKind`, extended with Swift 5.9+ kinds
internal enum ElementKind: String, RawRepresentable {
    case `associatedtype` = "source.lang.swift.decl.associatedtype"
    case `class` = "source.lang.swift.decl.class"
    case `enum` = "source.lang.swift.decl.enum"
    case enumcase = "source.lang.swift.decl.enumcase"
    case enumelement = "source.lang.swift.decl.enumelement"
    case `extension` = "source.lang.swift.decl.extension"
    case extensionClass = "source.lang.swift.decl.extension.class"
    case extensionEnum = "source.lang.swift.decl.extension.enum"
    case extensionProtocol = "source.lang.swift.decl.extension.protocol"
    case extensionStruct = "source.lang.swift.decl.extension.struct"
    case functionAccessorAddress = "source.lang.swift.decl.function.accessor.address"
    case functionAccessorDidset = "source.lang.swift.decl.function.accessor.didset"
    case functionAccessorGetter = "source.lang.swift.decl.function.accessor.getter"
    case functionAccessorModify = "source.lang.swift.decl.function.accessor.modify"
    case functionAccessorMutableaddress = "source.lang.swift.decl.function.accessor.mutableaddress"
    case functionAccessorRead = "source.lang.swift.decl.function.accessor.read"
    case functionAccessorSetter = "source.lang.swift.decl.function.accessor.setter"
    case functionAccessorWillset = "source.lang.swift.decl.function.accessor.willset"
    case functionConstructor = "source.lang.swift.decl.function.constructor"
    case functionDestructor = "source.lang.swift.decl.function.destructor"
    case functionFree = "source.lang.swift.decl.function.free"
    case functionMethodClass = "source.lang.swift.decl.function.method.class"
    case functionMethodInstance = "source.lang.swift.decl.function.method.instance"
    case functionMethodStatic = "source.lang.swift.decl.function.method.static"
    case functionOperator = "source.lang.swift.decl.function.operator"
    case functionOperatorInfix = "source.lang.swift.decl.function.operator.infix"
    case functionOperatorPostfix = "source.lang.swift.decl.function.operator.postfix"
    case functionOperatorPrefix = "source.lang.swift.decl.function.operator.prefix"
    case functionSubscript = "source.lang.swift.decl.function.subscript"
    case genericTypeParam = "source.lang.swift.decl.generic_type_param"
    case module = "source.lang.swift.decl.module"
    case opaqueType = "source.lang.swift.decl.opaquetype"
    case precedenceGroup = "source.lang.swift.decl.precedencegroup"
    case `protocol` = "source.lang.swift.decl.protocol"
    case `struct` = "source.lang.swift.decl.struct"
    case `typealias` = "source.lang.swift.decl.typealias"
    case varClass = "source.lang.swift.decl.var.class"
    case varGlobal = "source.lang.swift.decl.var.global"
    case varInstance = "source.lang.swift.decl.var.instance"
    case varLocal = "source.lang.swift.decl.var.local"
    case varParameter = "source.lang.swift.decl.var.parameter"
    case varStatic = "source.lang.swift.decl.var.static"
    /// Swift 5.5+: actor type declaration
    case actor = "source.lang.swift.decl.actor"
    /// Swift 5.9+: macro declaration
    case macro = "source.lang.swift.decl.macro"
    case other
}

extension ElementKind: Codable {}

extension ElementKind: UnknownCaseRepresentable {
    static let unknownCase: ElementKind = .other
}
