import Foundation

/// Where a declaration lives in the source tree.
///
/// Attached to `LayoutNode` so the Studio app can navigate from a diagram
/// element back to the file and line that declared it. Line and column are
/// 1-based, matching SwiftSyntax's `SourceLocationConverter`.
public struct SourceLocation: Sendable, Equatable, Hashable, Codable {
    public let filePath: String
    public let line: Int
    public let column: Int

    public init(filePath: String, line: Int, column: Int) {
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}
