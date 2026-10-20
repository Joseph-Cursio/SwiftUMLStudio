import Foundation

/// The modules each module of a package re-exports with `@_exported import`, so a declaration's
/// `imports` can name every module whose declarations its file sees, as `TypeLookup` reads them
/// (#124). Swift lets an `@_exported import Core` in any file of Analytics show Core's types to
/// every file of Analytics and to every file that imports Analytics, and so on down a chain of
/// re-exports: then `Analytics.Event` in such a file is the `Event` of Core's `enum Analytics`.
struct ModuleReexports {
    /// The modules re-exported, by every name Swift code can write the re-exporting module by
    /// (`ModuleQualifiers.c99Name(of:)`).
    private var reexportsForModule: [String: Set<String>] = [:]

    /// Records that a file of `module` re-exports `reexports`.
    mutating func record(_ reexports: Set<String>, from module: String) {
        guard !reexports.isEmpty else { return }
        reexportsForModule[module, default: []].formUnion(reexports)
        reexportsForModule[ModuleQualifiers.c99Name(of: module), default: []].formUnion(reexports)
    }

    /// `imports`, a file's in `module`, with every module they or `module` re-export, transitively.
    func widened(_ imports: Set<String>, in module: String?) -> Set<String> {
        var seen = imports
        var pending = Array(imports) + (module.map { [$0] } ?? [])
        while let next = pending.popLast() {
            for reexported in reexports(through: next) where seen.insert(reexported).inserted {
                pending.append(reexported)
            }
        }
        return seen
    }

    /// What `entry`, a module or a scoped import of one (`Mid.Analytics`, as
    /// `ImportExtractor.importedModules` records `import enum Mid.Analytics`), shows through the
    /// module's re-exports: every module it re-exports, or for a scoped import the declaration it
    /// names in each of them, as Swift finds `Analytics` in the `Core` that Mid re-exports.
    private func reexports(through entry: String) -> [String] {
        guard let dot = entry.firstIndex(of: ".") else { return Array(reexportsForModule[entry] ?? []) }
        let name = entry[entry.index(after: dot)...]
        return (reexportsForModule[String(entry[..<dot])] ?? []).compactMap { reexported in
            guard let reexportedDot = reexported.firstIndex(of: ".") else { return "\(reexported).\(name)" }
            return reexported[reexported.index(after: reexportedDot)...] == name ? reexported : nil
        }
    }

    /// Widens (`widened(_:in:)`) the `imports` of every structure in `items`, members included.
    func widenImports(of items: [SyntaxStructure]) {
        guard !reexportsForModule.isEmpty else { return }
        func widen(_ item: SyntaxStructure) {
            if let imports = item.imports { item.imports = widened(imports, in: item.module) }
            item.substructure?.forEach(widen)
        }
        items.forEach(widen)
    }
}
