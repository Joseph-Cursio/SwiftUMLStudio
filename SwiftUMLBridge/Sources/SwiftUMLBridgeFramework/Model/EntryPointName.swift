import Foundation

/// The `Type.method` a sequence or activity diagram starts from, read from what was typed or
/// picked. The method is what follows the last dot, and the type everything before it, so a
/// method of a nested type, as `extension NS.Real { func run() }`, is `NS.Real.run`, the name
/// `SequenceDiagramGenerating/findEntryPoints(for:)` lists it under (#234). The CLI's `--entry`
/// and the Studio's entry field both read names here, so the two cannot disagree on what a name
/// means. A module-qualified name, as `MyModule.Loader.load`, reads as a type `MyModule.Loader`,
/// which no type is filed under, so it draws an empty diagram.
public struct EntryPointName: Equatable, Sendable {
    /// The type, whole: `NS.Real` for `NS.Real.run`.
    public let type: String
    /// The method: `run` for `NS.Real.run`.
    public let method: String

    /// Reads `written`, or `nil` when it is not a type and a method joined by a dot: with no dot,
    /// or with a part left empty by a leading, trailing or doubled dot.
    public init?(_ written: String) {
        let parts = written.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts.contains(where: \.isEmpty), let method = parts.last else { return nil }
        self.type = parts.dropLast().joined(separator: ".")
        self.method = String(method)
    }
}
