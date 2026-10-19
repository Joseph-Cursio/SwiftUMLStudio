import Foundation

/// Swift type representing an AST element (analogue to SourceKitten's Structure).
///
/// - Concurrency safety: This mutable reference type is marked `@unchecked Sendable` because it is
///   constructed synchronously on a single thread (inside a `Task.detached` closure) and then handed
///   back to the `@MainActor` for read-only consumption. No concurrent mutation occurs.
///   Class-diagram preparation, which does edit structures, works on a private copy
///   (`preparedForClassDiagram(with:)`), so parsed structures stay read-only after construction.
///   **If parallel file processing is ever added (e.g., via a task group), this type must be
///   restructured as a value type or actor-isolated type to avoid data races.**
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

    // A new stored property must also be copied in `init(copying:)` and listed in
    // `SyntaxStructureCloneTests.storedProperties`.

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
    /// typename; for a `.typealias`, the name of the type it aliases (#125)
    internal let typename: String?

    internal var memberSuffix: String?

    internal var parent: SyntaxStructure?

    /// Where this declaration lives in the source. Populated by
    /// `SyntaxStructureBuilder` from a `SourceLocationConverter`; absent for
    /// synthesized structures (e.g. inheritance-clause type references) and for
    /// any structure decoded from JSON.
    internal var sourceLocation: SourceLocation?

    /// SPM target / module the declaration belongs to. Populated by
    /// `SyntaxStructureProvider.create(from:sdkPath:module:)` when the caller
    /// knows the source file's owning target; nil otherwise.
    internal var module: String?

    /// The modules the declaration's file imports, first path component only (`Foundation` for
    /// `import Foundation.NSString`). Stamped by `SyntaxStructureBuilder`; nil when unknown, as
    /// for a hand-built or decoded structure. A module qualifier in the file can name only these
    /// and its own module (#124).
    internal var imports: Set<String>?

    /// Set by `mergeExtensions` on an extension it merges away: the item that now shows its
    /// members. A type nested in that extension keeps the extension as its `parent`, which its
    /// name, scope and access come from, and is drawn hanging off this item (`nestingParent`).
    internal var mergedInto: SyntaxStructure?

    /// Set by `mergeExtensions` on the item extensions merge into: the supertypes their
    /// inheritance clauses name, in merge order, each with the scope of the extension that names
    /// it. They are drawn from this item's box, as its own supertypes are (#76).
    internal var carriedSupertypes: [CarriedSupertype] = []

    /// Set by `mergeExtensions` on the extension a hidden type's extensions merge into: that type.
    /// The extension's box stands in for it, so an edge to the type ends there however the edge
    /// spells it (#153, #124).
    internal var standsInFor: SyntaxStructure?

    /// The generic arguments an extension's extended type binds on its last component, as
    /// written: `Int` for `extension Foo<Int>`, `String, Int` for `extension [String: Int]`.
    /// `name` holds the type without them (`Foo`, `Dictionary`), so the extension is drawn,
    /// linked, merged and excluded as one of that type; emitters only show these beside it (#66).
    internal var boundGenericArguments: String?

    /// Whether an extension writes the type it extends with sugar, or a typealias the type it
    /// aliases: `[Int]`, `[String: Int]`, `Int?` (`TypeSyntax.isSugared`). `name`, or a
    /// typealias's `typename`, is then the standard-library type's (`Array`, `Dictionary`,
    /// `Optional`), which the sugar always means, even where the project declares a type of that
    /// name; past a member path (`Array.Stats` for `[Int].Stats`), only the base is.
    /// `TypeLookup.extendedType(of:)` reads it, so a project's own `Array` is not the type
    /// `extension [Int]` extends (#126).
    internal var isSugared = false

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

    /// A copy of `original` that shares every field preparation never writes, and has no
    /// `substructure` or `parent` yet: `clonedForest(of:)` fills those in. It is a designated init
    /// on purpose, so a new `let` fails to compile until it is copied here; a new `var` is caught
    /// by `SyntaxStructureCloneTests.storedPropertiesArePinned` instead.
    private init(copying original: SyntaxStructure) {
        accessibility = original.accessibility
        attribute = original.attribute
        attributes = original.attributes
        elements = original.elements
        inheritedTypes = original.inheritedTypes
        kind = original.kind
        name = original.name
        runtimename = original.runtimename
        typename = original.typename
        memberSuffix = original.memberSuffix
        sourceLocation = original.sourceLocation
        module = original.module
        imports = original.imports
        carriedSupertypes = original.carriedSupertypes
        boundGenericArguments = original.boundGenericArguments
        isSugared = original.isSugared
        super.init()
    }

    /// A private copy of every structure reachable from `roots` through `substructure`, members
    /// included, for class-diagram preparation to edit without touching the parsed structures (#73).
    ///
    /// - A structure reached twice is copied once, so the copies alias exactly as the originals do.
    /// - `parent` points at the parent's copy, or at the original parent when that lies outside the
    ///   forest: preparation only reads such a parent, never writes it.
    /// - `inheritedTypes`, `attributes` and `elements` are shared, since nothing writes them.
    static func clonedForest(of roots: [SyntaxStructure]) -> [SyntaxStructure] {
        var copies: [ObjectIdentifier: SyntaxStructure] = [:]
        // Keeps every original alive until the parents are re-pointed, so no identifier is reused.
        var pairs: [(original: SyntaxStructure, clone: SyntaxStructure)] = []

        func clone(_ original: SyntaxStructure) -> SyntaxStructure {
            if let existing = copies[ObjectIdentifier(original)] { return existing }
            let duplicate = SyntaxStructure(copying: original)
            copies[ObjectIdentifier(original)] = duplicate
            pairs.append((original, duplicate))
            duplicate.substructure = original.substructure?.map(clone)
            return duplicate
        }

        let clonedRoots = roots.map(clone)
        for pair in pairs {
            pair.clone.parent = pair.original.parent.map { copies[ObjectIdentifier($0)] ?? $0 }
            pair.clone.mergedInto = pair.original.mergedInto.map { copies[ObjectIdentifier($0)] ?? $0 }
            pair.clone.standsInFor = pair.original.standsInFor.map { copies[ObjectIdentifier($0)] ?? $0 }
        }
        return clonedRoots
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

// Parallel List Drift pairs this with the app's `AccessLevel` enum, but this maps SourceKit's
// own accessibility keys (raw values `source.lang.swift.accessibility.*`) — a distinct layer.
// swiftprojectlint:disable:next parallel-list-drift
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
