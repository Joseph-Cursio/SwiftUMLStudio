import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// Several include or exclude entries, as repeated `--exclude` flags or a
/// multi-entry `files.exclude` in `.swiftumlbridge.yml` produce them. Every
/// exclude entry applies, a file matching several include entries comes back
/// once, and the result keeps enumeration order whatever order the entries
/// were listed in.
@Suite("FileCollector — several include and exclude entries")
struct FileCollectorMultipleGlobTests {

    /// `<root>/Sources/{App.swift, Generated/Gen.swift, Mocks/MockA.swift}`,
    /// the layout of the `--exclude` example in `docs/user/reference.md`.
    private struct Fixture {
        let root: URL

        init() throws {
            let manager = FileManager.default
            root = manager.temporaryDirectory
                .appendingPathComponent("FileCollectorMultipleGlobTests-\(UUID().uuidString)")
            for path in ["Sources/App.swift", "Sources/Generated/Gen.swift", "Sources/Mocks/MockA.swift"] {
                let file = root.appendingPathComponent(path)
                try manager.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("struct \(file.deletingPathExtension().lastPathComponent) {}\n".utf8)
                    .write(to: file)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private let collector = FileCollector()

    /// Names sorted but not de-duplicated, so a file returned twice shows up.
    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent).sorted()
    }

    @Test("every exclude entry applies, not only the last")
    func everyExcludeApplies() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/Gen*.swift", "**/Mock*.swift"]
        let files = collector.getFiles(for: ["."], in: fixture.root.path, honoring: options)
        #expect(names(files) == ["App.swift"])
    }

    @Test("the documented --exclude example drops both directories")
    func documentedDirectoryExcludes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["Sources/Generated/", "Sources/Mocks/"]
        let files = collector.getFiles(for: ["Sources"], in: fixture.root.path, honoring: options)
        #expect(names(files) == ["App.swift"])
    }

    @Test("a file matching two include entries is returned once")
    func overlappingIncludesDoNotDuplicate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["**/Gen*.swift", "Sources/Generated/*.swift", "**/Mock*.swift"]
        let files = collector.getFiles(for: ["."], in: fixture.root.path, honoring: options)
        #expect(names(files) == ["Gen.swift", "MockA.swift"])
    }

    @Test("include results keep enumeration order, not the order the entries are listed in")
    func includeKeepsEnumerationOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let enumerated = collector.getFiles(for: ["."], in: fixture.root.path)
            .map(\.lastPathComponent)
            .filter { $0 != "App.swift" }
        try #require(enumerated.count == 2)
        var options = FileOptions()
        options.include = enumerated.reversed().map { "**/\($0)" }
        let files = collector.getFiles(for: ["."], in: fixture.root.path, honoring: options)
        #expect(files.map(\.lastPathComponent) == enumerated)
    }

    @Test("include with two exclude entries drops both and duplicates nothing")
    func includeWithTwoExcludes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["**/*.swift"]
        options.exclude = ["**/Gen*.swift", "**/Mock*.swift"]
        let files = collector.getFiles(for: ["."], in: fixture.root.path, honoring: options)
        #expect(names(files) == ["App.swift"])
    }
}
