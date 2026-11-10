import Foundation

// MARK: - Helpers

// Internal rather than private so a test can call it directly.
extension ComponentScript {
    /// Convert a target name into a valid PlantUML / Mermaid identifier.
    static func safeAlias(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "+", with: "_")
    }
}
