import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Include/exclude globs under a search directory whose real path contains glob
/// syntax — a folder named `Proj [old]`, say. A relative entry is anchored at
/// that directory, and the directory is a literal path: its `[old]` is not a
/// character class, nor its `*` or `?` a wildcard. Read as glob syntax, `[old]`
/// matched neither the directory itself nor anything under it, and `*` or `?`
/// let an entry reach into sibling directories.
@Suite("FileCollector — glob syntax in the search directory's name")
struct FileCollectorGlobAnchorTests {

    /// `<root>/<name>/Sub/{MockA,Real}.swift`, plus `<root>/<sibling>/Sub/MockA.swift`,
    /// a directory `name` would match were it read as a glob.
    private struct Fixture {
        let root: URL
        let project: URL
        let sibling: URL

        init(name: String, sibling siblingName: String = "Sibling") throws {
            let manager = FileManager.default
            root = manager.temporaryDirectory
                .appendingPathComponent("FileCollectorGlobAnchorTests-\(UUID().uuidString)")
            project = root.appendingPathComponent(name)
            sibling = root.appendingPathComponent(siblingName)
            for (directory, names) in [(project, ["MockA.swift", "Real.swift"]), (sibling, ["MockA.swift"])] {
                let sub = directory.appendingPathComponent("Sub")
                try manager.createDirectory(at: sub, withIntermediateDirectories: true)
                for name in names {
                    try Data("struct \(name.dropLast(6)) {}\n".utf8)
                        .write(to: sub.appendingPathComponent(name))
                }
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func names(_ urls: [URL]) -> Set<String> {
        Set(urls.map(\.lastPathComponent))
    }

    private static let directoryNames = ["Proj [old]", "Proj*", "Proj?", "Proj {a,b}"]

    @Test("an include glob selects files under the search directory", arguments: directoryNames)
    func includeUnderGlobSyntaxDirectory(name: String) throws {
        let fixture = try Fixture(name: name)
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: fixture.project.path, honoring: options)
        #expect(names(files) == ["MockA.swift"])
    }

    @Test("an exclude glob drops files under the search directory", arguments: directoryNames)
    func excludeUnderGlobSyntaxDirectory(name: String) throws {
        let fixture = try Fixture(name: name)
        defer { fixture.remove() }
        var options = FileOptions()
        options.exclude = ["**/Mock*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: fixture.project.path, honoring: options)
        #expect(names(files) == ["Real.swift"])
    }

    @Test("a glob with plain directories before its pattern selects files", arguments: directoryNames)
    func includeWithPlainLeadingDirectory(name: String) throws {
        let fixture = try Fixture(name: name)
        defer { fixture.remove() }
        var options = FileOptions()
        options.include = ["Sub/Mock*.swift"]
        let files = FileCollector().getFiles(for: ["."], in: fixture.project.path, honoring: options)
        #expect(names(files) == ["MockA.swift"])
    }

    @Test(
        "a glob anchored at the search directory does not reach a sibling it would match as a glob",
        arguments: [("Proj [old]", "Proj o"), ("Proj*", "ProjX"), ("Proj?", "ProjX")]
    )
    func globDoesNotMatchSibling(name: String, sibling: String) throws {
        let fixture = try Fixture(name: name, sibling: sibling)
        defer { fixture.remove() }
        let globs = expandGlobs("**/Mock*.swift", in: fixture.project.path)
        let own = canonicalPath(fixture.project.path) + "/Sub/MockA.swift"
        let other = canonicalPath(fixture.sibling.path) + "/Sub/MockA.swift"
        #expect(globs.contains { $0.matches(own) })
        #expect(globs.contains { $0.matches(other) } == false)
    }

    @Test("an absolute glob anchored at the root still matches")
    func rootAnchoredGlob() throws {
        let fixture = try Fixture(name: "Proj [old]")
        defer { fixture.remove() }
        let globs = expandGlobs("/**/Mock*.swift", in: fixture.project.path)
        #expect(globs.contains { $0.matches(canonicalPath(fixture.project.path) + "/Sub/MockA.swift") })
        #expect(globs.contains { $0.matches(canonicalPath(fixture.project.path) + "/Sub/Real.swift") } == false)
    }

    @Test("Glob.description spells the search directory as it is named", arguments: directoryNames)
    func descriptionKeepsDirectoryName(name: String) throws {
        let fixture = try Fixture(name: name)
        defer { fixture.remove() }
        let globs = expandGlobs("**/Mock*.swift", in: fixture.project.path)
        #expect(globs.map(\.description) == [canonicalPath(fixture.project.path) + "/**/Mock*.swift"])
    }
}
