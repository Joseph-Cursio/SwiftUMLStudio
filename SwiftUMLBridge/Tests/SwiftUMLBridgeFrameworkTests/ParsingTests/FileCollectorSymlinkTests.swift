import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Include/exclude globs for a directory spelled through a symlink. Directory
/// enumeration reports entries under the directory's resolved path, so a glob
/// anchored at the spelling the caller passed has to be resolved the same way.
/// `/tmp` → `/private/tmp` is the everyday case — the `Bundle.module` fixture
/// path of a checkout under `/tmp` reads `/tmp/…` while its enumerated files
/// read `/private/tmp/…` — and a symlinked parent reproduces it anywhere.
/// A search directory that is itself a symlink is walked through the link.
@Suite("FileCollector — directory spelled through a symlink")
struct FileCollectorSymlinkTests {

    /// `<root>/real/proj/Sub/{MockA,Real}.swift`, plus `<root>/alias` → `real`,
    /// so `<root>/alias/proj` names the project through a symlinked parent,
    /// and `<root>/link` → `real/proj`, a symlink to the project itself.
    private struct Fixture {
        let root: URL
        var realProject: URL { root.appendingPathComponent("real/proj") }
        var aliasedProject: URL { root.appendingPathComponent("alias/proj") }
        var linkedProject: URL { root.appendingPathComponent("link") }

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
            try manager.createSymbolicLink(
                at: root.appendingPathComponent("link"),
                withDestinationURL: root.appendingPathComponent("real/proj")
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
        let directory = try resolvedProject(fixture)
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

    // MARK: - A search directory that is itself a symlink

    /// Whether every URL names a regular file — that is, the link was walked
    /// rather than handed back as though it were a source file.
    private func allRegularFiles(_ urls: [URL]) -> Bool {
        urls.allSatisfy { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }
    }

    @Test("a search directory that is a symlink is walked through the link")
    func walksLinkedDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let files = FileCollector().getFiles(for: fixture.linkedProject)
        #expect(names(files) == ["MockA.swift", "Real.swift"])
        #expect(allRegularFiles(files))
    }

    @Test("a symlinked directory named relative to the search directory is walked")
    func walksLinkedDirectoryByRelativePath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let files = FileCollector().getFiles(for: ["link"], in: fixture.root.path, honoring: nil)
        #expect(names(files) == ["MockA.swift", "Real.swift"])
        #expect(allRegularFiles(files))
    }

    @Test("include and exclude globs apply when the search directory is a symlink")
    func globsUnderLinkedDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = fixture.linkedProject.path
        var include = FileOptions()
        include.include = ["**/Mock*.swift"]
        let included = FileCollector().getFiles(for: ["."], in: directory, honoring: include)
        #expect(names(included) == ["MockA.swift"])

        var exclude = FileOptions()
        exclude.exclude = ["**/Mock*.swift"]
        let remaining = FileCollector().getFiles(for: ["."], in: directory, honoring: exclude)
        #expect(names(remaining) == ["Real.swift"])
    }
}

// MARK: - An entry spelled through a symlink

/// An absolute entry names its own directory rather than using the search
/// directory, so resolving the search directory does not reach it (#59), and a
/// relative entry can run through a symlink below the search directory.
extension FileCollectorSymlinkTests {

    /// The project as the CLI passes its search directory: already resolved.
    private func resolvedProject(_ fixture: Fixture) throws -> String {
        try #require(fixture.realProject.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
    }

    @Test("an absolute include glob matches whether or not it is spelled through a symlink")
    func absoluteIncludeGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = try resolvedProject(fixture)
        for project in [fixture.aliasedProject.path, directory] {
            var options = FileOptions()
            options.include = [project + "/**/Mock*.swift"]
            let files = FileCollector().getFiles(for: ["."], in: directory, honoring: options)
            #expect(names(files) == ["MockA.swift"], "include anchored at \(project)")
        }
    }

    @Test("an absolute exclude glob drops files whether or not it is spelled through a symlink")
    func absoluteExcludeGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = try resolvedProject(fixture)
        for project in [fixture.aliasedProject.path, directory] {
            var options = FileOptions()
            options.exclude = [project + "/**/Mock*.swift"]
            let files = FileCollector().getFiles(for: ["."], in: directory, honoring: options)
            #expect(names(files) == ["Real.swift"], "exclude anchored at \(project)")
        }
    }

    @Test("an absolute entry with no glob syntax matches when spelled through a symlink")
    func absoluteLiteralEntries() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // `alias` → `real` is no `/private` prefix, so the substring match a
        // literal entry falls back on cannot paper over the other spelling.
        let directory = try resolvedProject(fixture)
        let sub = fixture.aliasedProject.appendingPathComponent("Sub")
        var include = FileOptions()
        include.include = [sub.path]
        let included = FileCollector().getFiles(for: ["."], in: directory, honoring: include)
        #expect(names(included) == ["MockA.swift", "Real.swift"])

        var exclude = FileOptions()
        exclude.exclude = [sub.appendingPathComponent("MockA.swift").path]
        let remaining = FileCollector().getFiles(for: ["."], in: directory, honoring: exclude)
        #expect(names(remaining) == ["Real.swift"])
    }

    @Test("a relative entry that runs through a symlink below the search directory matches")
    func relativeEntryThroughSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // The walk from the root does not descend `link` or `alias`; it finds
        // the files under `real`, where both symlinks lead.
        let directory = fixture.root.path
        var include = FileOptions()
        include.include = ["link/**/Mock*.swift"]
        let included = FileCollector().getFiles(for: ["."], in: directory, honoring: include)
        #expect(names(included) == ["MockA.swift"])

        var exclude = FileOptions()
        exclude.exclude = ["alias/proj/Sub/Mock*.swift"]
        let remaining = FileCollector().getFiles(for: ["."], in: directory, honoring: exclude)
        #expect(names(remaining) == ["Real.swift"])
    }

    @Test("an exclude entry naming a symlinked file drops that file, not its target")
    func literalEntryKeepsFileName() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sub = fixture.realProject.appendingPathComponent("Sub")
        try FileManager.default.createSymbolicLink(
            at: sub.appendingPathComponent("Alias.swift"),
            withDestinationURL: sub.appendingPathComponent("Real.swift")
        )
        var options = FileOptions()
        options.exclude = ["Sub/Alias.swift"]
        let files = FileCollector().getFiles(
            for: ["Sub/Alias.swift", "Sub/Real.swift"],
            in: try resolvedProject(fixture), honoring: options
        )
        #expect(names(files) == ["Real.swift"])
    }

    @Test("a literal entry naming a symlinked directory matches the files it leads to")
    func literalEntryNamingSymlinkedDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // The walk from the root does not descend `link`; its files are found
        // under `real/proj`, which is where the entry physically points.
        let directory = fixture.root.path
        var include = FileOptions()
        include.include = ["link"]
        let included = FileCollector().getFiles(for: ["."], in: directory, honoring: include)
        #expect(names(included) == ["MockA.swift", "Real.swift"])

        var exclude = FileOptions()
        exclude.exclude = ["link"]
        let remaining = FileCollector().getFiles(for: ["."], in: directory, honoring: exclude)
        #expect(remaining.isEmpty)
    }

    @Test("a literal entry spelled through a symlink matches in a list that also holds a glob")
    func literalEntryBesideGlob() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        let literal = fixture.aliasedProject.appendingPathComponent("Sub/MockA.swift").path
        options.include = [literal, "**/Nothing*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: try resolvedProject(fixture), honoring: options)
        #expect(names(files) == ["MockA.swift"])
    }

    @Test("a brace group after a prefix spelled through a symlink matches")
    func braceGroupAfterSymlinkedPrefix() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = [fixture.aliasedProject.path + "/{Sub,None}/Mock*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: try resolvedProject(fixture), honoring: options)
        #expect(names(files) == ["MockA.swift"])
    }

    @Test("a glob matches under a directory whose name is stored composed")
    func composedDirectoryName() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // `mkdir` in a shell, or a git checkout, stores `é` as U+00E9.
        // FileManager, or a path built with URL, would store it decomposed
        // and hide the difference, so the name is spelled as a String.
        let project = fixture.root.path + "/D\u{E9}v"
        let made = project.withCString { mkdir($0, 0o755) }
        try #require(made == 0)
        let sub = URL(fileURLWithPath: project).appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["MockA.swift", "Real.swift"] {
            try Data("struct \(name.dropLast(6)) {}\n".utf8).write(to: sub.appendingPathComponent(name))
        }
        var options = FileOptions()
        options.include = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: project, honoring: options)
        #expect(names(files) == ["MockA.swift"])
    }
}
