import Foundation
import Testing
@testable import SwiftUMLStudio

@Suite("SecurityScopedURL")
struct SecurityScopedURLTests {

    @Test("makeBookmark + resolveURL round-trip for a real file")
    func roundTripExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SUS-bookmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try #require(SecurityScopedURL.makeBookmark(for: directory))
        #expect(!bookmark.isEmpty)

        let resolved = try #require(SecurityScopedURL.resolveURL(from: bookmark))
        // Compare standardized URLs: macOS resolves `/var` to its canonical
        // `/private/var` form via the firmlink, and the resolved URL may carry
        // a trailing slash the original lacks.
        #expect(resolved.url.standardizedFileURL == directory.standardizedFileURL)
        #expect(resolved.isStale == false)
    }

    @Test("resolveURL returns nil for garbage bookmark data")
    func resolveRejectsGarbage() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02])
        #expect(SecurityScopedURL.resolveURL(from: garbage) == nil)
    }

    @Test("makeBookmark returns nil for unreachable file URL")
    func makeBookmarkRejectsUnreachable() {
        let nonexistent = URL(fileURLWithPath: "/var/empty/SUS-bookmark-does-not-exist-\(UUID().uuidString)")
        #expect(SecurityScopedURL.makeBookmark(for: nonexistent) == nil)
    }
}
