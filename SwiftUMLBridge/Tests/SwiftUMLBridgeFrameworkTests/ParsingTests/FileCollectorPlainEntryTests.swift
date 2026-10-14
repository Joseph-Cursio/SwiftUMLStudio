import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A plain include or exclude entry names a file or directory: that path and what lies inside
/// it. It used to take every path that merely began with the same text, so excluding
/// `Sources/App` also dropped `Sources/AppKit/` and `Sources/AppDelegate.swift` (#111).
@Suite("FileCollector — plain entries stop at a path component")
struct FileCollectorPlainEntryTests {

    private struct Fixture {
        static let files = [
            "Sources/App/A.swift", "Sources/App/Sub/B.swift", "Sources/AppKit/K.swift",
            "Sources/AppDelegate.swift", "Sources/Core/C.swift", "Generated/G.swift", "GeneratedExtra/E.swift"
        ]

        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileCollectorPlainEntryTests-\(UUID().uuidString)")
            for file in Self.files {
                let url = root.appendingPathComponent(file)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data("struct Z {}\n".utf8).write(to: url)
            }
        }

        func collected(include: [String] = [], exclude: [String] = []) -> [String] {
            var options = FileOptions()
            options.include = include
            options.exclude = exclude
            let prefix = canonicalPath(root.path) + "/"
            return FileCollector().getFiles(for: ["."], in: root.path, honoring: options)
                .map { String(enumeratedPath(of: $0).dropFirst(prefix.count)) }
                .sorted()
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("excluding a directory leaves its prefix siblings")
    func excludeDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.collected(exclude: ["Sources/App"]) == [
            "Generated/G.swift", "GeneratedExtra/E.swift", "Sources/AppDelegate.swift",
            "Sources/AppKit/K.swift", "Sources/Core/C.swift"
        ])
        #expect(fixture.collected(exclude: ["Generated"]).contains("GeneratedExtra/E.swift"))
    }

    @Test("including a directory takes only what is inside it")
    func includeDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.collected(include: ["Sources/App"]) == ["Sources/App/A.swift", "Sources/App/Sub/B.swift"])
    }

    @Test("a plain entry beside a glob, and a brace group of plain options, stop at a component too")
    func plainEntryInGlobList() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.collected(include: ["Sources/App", "**/C.swift"]) == [
            "Sources/App/A.swift", "Sources/App/Sub/B.swift", "Sources/Core/C.swift"
        ])
        #expect(fixture.collected(include: ["Sources/{App,Core}"]) == [
            "Sources/App/A.swift", "Sources/App/Sub/B.swift", "Sources/Core/C.swift"
        ])
    }

    @Test("a plain file entry takes that file only")
    func plainFileEntry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(fixture.collected(include: ["Sources/App/A.swift"]) == ["Sources/App/A.swift"])
    }
}
