import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Include/exclude globs for a directory spelled through a symlink. Directory
/// enumeration reports entries under the directory's resolved path, so a glob
/// anchored at the spelling the caller passed has to be resolved the same way.
/// `/tmp` → `/private/tmp` is the everyday case — the `Bundle.module` fixture
/// path of a checkout under `/tmp` reads `/tmp/…` while its enumerated files
/// read `/private/tmp/…` — and a symlinked parent reproduces it anywhere.
@Suite("FileCollector — directory spelled through a symlink")
struct FileCollectorSymlinkTests {

    /// `<root>/real/proj/Sub/{MockA,Real}.swift`, plus `<root>/alias` → `real`,
    /// so `<root>/alias/proj` names the project through a symlink.
    private struct Fixture {
        let root: URL
        var realProject: URL { root.appendingPathComponent("real/proj") }
        var aliasedProject: URL { root.appendingPathComponent("alias/proj") }

        init() throws {
            let manager = FileManager.default
            root = manager.temporaryDirectory
                .appendingPathComponent("FileCollectorSymlinkTests-\(UUID().uuidString)")
            let sub = root.appendingPathComponent("real/proj/Sub")
            try manager.createDirectory(at: sub, withIntermediateDirectories: true)
            for name in ["MockA.swift", "Real.swift"] {
                try Data("struct \(name.dropLast(6)) {}\n".utf8)
                    .write(to: sub.appendingPathComponent(name))
            }
            try manager.createSymbolicLink(
                at: root.appendingPathComponent("alias"),
                withDestinationURL: root.appendingPathComponent("real")
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func names(_ urls: [URL]) -> Set<String> {
        Set(urls.map(\.lastPathComponent))
    }

    @Test("an include glob matches files under a symlinked directory")
    func includeThroughSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(
            for: ["."], in: fixture.aliasedProject.path, honoring: options
        )
        #expect(names(files) == ["MockA.swift"])
    }

    @Test("an exclude glob drops files under a symlinked directory")
    func excludeThroughSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(
            for: ["."], in: fixture.aliasedProject.path, honoring: options
        )
        #expect(names(files) == ["Real.swift"])
    }

    @Test("an exclude glob drops explicit files named relative to a symlinked directory")
    func excludeExplicitRelativeFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(
            for: ["Sub/MockA.swift", "Sub/Real.swift"],
            in: fixture.aliasedProject.path, honoring: options
        )
        #expect(names(files) == ["Real.swift"])
    }

    @Test("an exclude glob drops an explicit file spelled through a symlink")
    func excludeExplicitFileThroughSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/Mock*.swift"]
        // The CLI's search directory is the resolved working directory; the
        // file argument can still be typed through a symlink.
        let directory = try #require(
            fixture.realProject.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        )
        let sub = fixture.aliasedProject.appendingPathComponent("Sub")
        let files = FileCollector().getFiles(
            for: [sub.appendingPathComponent("MockA.swift").path, sub.appendingPathComponent("Real.swift").path],
            in: directory, honoring: options
        )
        #expect(names(files) == ["Real.swift"])
    }

    @Test("matchGlobs finds files under a symlinked directory")
    func matchGlobsThroughSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = fixture.aliasedProject.path
        let results = matchGlobs(expandGlobs("**/Mock*.swift", in: directory), in: directory)
        #expect(names(results) == ["MockA.swift"])
    }
}
