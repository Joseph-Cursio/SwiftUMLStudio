import Foundation

// https://github.com/jpsim/SourceKitten/blob/master/Source/SourceKittenFramework/SwiftDeclarationKind.swift
/// Analogous to SourceKittenFramework's `SwiftDeclarationKind`, extended with Swift 5.9+ kinds
internal enum ElementKind: String, RawRepresentable, Codable, UnknownCaseRepresentable {
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

    static let unknownCase: ElementKind = .other
}
