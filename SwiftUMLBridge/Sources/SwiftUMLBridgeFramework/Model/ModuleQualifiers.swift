import Foundation

/// The modules a class diagram's declarations belong to, under every name Swift code can write
/// one by, so `TypeLookup` can read `ModA.Foo` as the type `Foo` in module ModA (#124). In package
/// mode a declaration's module is its target's name, and Swift code names the module by the
/// target's C99 name, so both count: `my-lib` and `my_lib`.
struct ModuleQualifiers {
    private var modulesForQualifier: [String: Set<String>] = [:]
    private var writtenNameForModule: [String: String] = [:]

    mutating func record(_ module: String) {
        guard writtenNameForModule[module] == nil else { return }
        let written = Self.c99Name(of: module)
        writtenNameForModule[module] = written
        modulesForQualifier[module, default: []].insert(module)
        modulesForQualifier[written, default: []].insert(module)
    }

    /// The name Swift code writes for `module` (`c99Name(of:)`), worked out once for a module
    /// the diagram has seen: a lookup asks it for every candidate it weighs.
    func writtenName(of module: String) -> String {
        writtenNameForModule[module] ?? Self.c99Name(of: module)
    }

    /// Every name a qualifier can name a module by, in a fixed order.
    var qualifiers: [String] { modulesForQualifier.keys.sorted() }

    /// The modules `qualifier` can name; empty when it names none the diagram has seen.
    func modules(namedBy qualifier: String) -> Set<String> {
        modulesForQualifier[qualifier] ?? []
    }

    /// The name Swift code writes for the module of the target `name`, as SwiftPM derives a
    /// target's `c99name`: each character that cannot be in an identifier becomes `_`, and so
    /// does a leading digit, so `my-lib` is `my_lib` and `2D` is `_D`. ASCII follows SwiftPM
    /// exactly; beyond it, a Unicode letter or decimal digit is kept where SwiftPM keeps C99's
    /// Annex D ranges, which differ for a few symbols.
    static func c99Name(of name: String) -> String {
        var scalars = name.unicodeScalars.map { scalar -> Unicode.Scalar in
            let isIdentifier = scalar == "_" || scalar.properties.isAlphabetic
                || scalar.properties.numericType == .decimal
            return isIdentifier ? scalar : "_"
        }
        if let first = scalars.first, first.properties.numericType == .decimal {
            scalars[0] = "_"
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
