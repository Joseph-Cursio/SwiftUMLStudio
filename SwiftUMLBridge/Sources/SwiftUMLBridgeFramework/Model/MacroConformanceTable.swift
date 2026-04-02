import Foundation

/// Maps well-known Swift macro attribute names to the protocol conformances they synthetically generate.
///
/// Only macros whose synthesized conformances are part of the public Swift/Apple SDK contract are included.
/// Custom or third-party macros cannot be resolved because their expansions are not available at the syntax level.
/// To add support for additional macros, extend the `table` dictionary below.
enum MacroConformanceTable: Sendable {
    /// Returns the synthetic conformance protocol names for a given macro attribute name,
    /// or an empty array if the macro is not recognized.
    static func syntheticConformances(for macroName: String) -> [String] {
        table[macroName] ?? []
    }

    private static let table: [String: [String]] = [
        // Observation framework (Swift 5.9+ / iOS 17+)
        "Observable": ["Observable"],
        // SwiftData
        "Model": ["Observable", "PersistentModel"],
    ]
}
