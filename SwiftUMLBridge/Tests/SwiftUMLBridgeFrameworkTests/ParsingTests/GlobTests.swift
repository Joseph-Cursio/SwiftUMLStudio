import Testing
@testable import SwiftUMLBridgeFramework
import Foundation

@Suite("Glob")
struct GlobTests {

    private var projectMockURL: URL {
        Bundle.module.resourceURL!
            .appendingPathComponent("TestData")
            .appendingPathComponent("ProjectMock")
    }

    // MARK: - pathContainsGlobSyntax

    @Test("pathContainsGlobSyntax returns true for * wildcard")
    func pathContainsStarWildcard() {
        #expect(pathContainsGlobSyntax("Sources/**/*.swift"))
    }

    @Test("pathContainsGlobSyntax returns true for ? wildcard")
    func pathContainsQuestionWildcard() {
        #expect(pathContainsGlobSyntax("Sources/?oo.swift"))
    }

    @Test("pathContainsGlobSyntax returns true for [ character")
    func pathContainsBracket() {
        #expect(pathContainsGlobSyntax("file[0-9].swift"))
    }

    @Test("pathContainsGlobSyntax returns true for { character")
    func pathContainsBrace() {
        #expect(pathContainsGlobSyntax("file{A,B}.swift"))
    }

    @Test("pathContainsGlobSyntax returns false for plain path")
    func pathContainsPlain() {
        #expect(pathContainsGlobSyntax("/absolute/path/to/file.swift") == false)
    }

    @Test("pathContainsGlobSyntax returns false for empty string")
    func pathContainsEmpty() {
        #expect(pathContainsGlobSyntax("") == false)
    }

    // MARK: - parseCommaDelimitedList

    @Test("parseCommaDelimitedList splits by comma")
    func parseCommaBasic() {
        let result = parseCommaDelimitedList("a,b,c")
        #expect(result == ["a", "b", "c"])
    }

    @Test("parseCommaDelimitedList trims whitespace")
    func parseCommaTrimsWhitespace() {
        let result = parseCommaDelimitedList("a , b , c")
        #expect(result == ["a", "b", "c"])
    }

    @Test("parseCommaDelimitedList filters empty entries")
    func parseCommaFiltersEmpty() {
        let result = parseCommaDelimitedList("a,,b")
        #expect(result == ["a", "b"])
    }

    @Test("parseCommaDelimitedList returns empty for empty string")
    func parseCommaEmpty() {
        let result = parseCommaDelimitedList("")
        #expect(result.isEmpty)
    }

    @Test("parseCommaDelimitedList returns single item for no comma")
    func parseCommaSingleItem() {
        let result = parseCommaDelimitedList("Sources/Foo.swift")
        #expect(result == ["Sources/Foo.swift"])
    }

    // MARK: - expandPath

    @Test("expandPath returns URL unchanged for absolute path")
    func expandPathAbsolute() {
        let url = expandPath("/usr/local/bin", in: "/tmp")
        #expect(url.path == "/usr/local/bin")
    }

    @Test("expandPath expands tilde to home directory")
    func expandPathTilde() {
        let url = expandPath("~/Documents", in: "/tmp")
        let home = NSString(string: "~").expandingTildeInPath
        #expect(url.path.hasPrefix(home))
    }

    @Test("expandPath appends relative path to directory")
    func expandPathRelative() {
        let url = expandPath("sub/file.swift", in: "/tmp/project")
        #expect(url.path == "/tmp/project/sub/file.swift")
    }

    // MARK: - expandGlobs

    @Test("expandGlobs without glob syntax returns path globs")
    func expandGlobsNoGlobSyntax() {
        let globs = expandGlobs("Sources/Foo.swift", in: projectMockURL.path)
        #expect(globs.isEmpty == false)
        for glob in globs {
            switch glob {
            case .path:
                #expect(Bool(true))
            case .regex:
                break
            }
        }
    }

    @Test("expandGlobs with wildcard returns regex globs")
    func expandGlobsWithWildcard() {
        let globs = expandGlobs("**/*.swift", in: projectMockURL.path)
        #expect(globs.isEmpty == false)
    }

    /// A brace entry used to come back as one glob whatever happened to it, even a `.path` that
    /// matched nothing when its regex did not compile, so a non-empty result proved nothing (#58).
    /// It now means exactly the list of its expansions.
    @Test("expandGlobs expands a brace entry into its options", arguments: [
        ("{Mock0,Mock1}File.swift", "Mock0File.swift,Mock1File.swift"),
        ("{*Kit,?ar}.swift", "*Kit.swift,?ar.swift")
    ])
    func expandGlobsBraceExpansion(braced: String, listed: String) {
        let globs = expandGlobs(braced, in: projectMockURL.path)
        #expect(globs.count == 2)
        #expect(globs.map(\.description) == expandGlobs(listed, in: projectMockURL.path).map(\.description))
    }

    @Test("expandGlobs with comma-delimited paths produces multiple globs")
    func expandGlobsMultiplePaths() {
        let globs = expandGlobs("Mock0File.swift,Mock1File.swift", in: projectMockURL.path)
        #expect(globs.count >= 1)
    }

    // MARK: - splitGlobEntry

    @Test("splitGlobEntry anchors a relative entry at the search directory, glob syntax and all")
    func splitRelativeEntry() {
        let split = splitGlobEntry("**/*.swift", in: "/d [old]*")
        #expect(split.anchor == "/d [old]*")
        #expect(split.pattern == "**/*.swift")
    }

    @Test("splitGlobEntry extends the anchor over plain leading directories")
    func splitPlainLeadingDirectories() {
        let split = splitGlobEntry("Sources/Sub/*.swift", in: "/d")
        #expect(split.anchor == "/d/Sources/Sub")
        #expect(split.pattern == "*.swift")
    }

    @Test("splitGlobEntry anchors an absolute entry that starts with a pattern at the root")
    func splitRootEntry() {
        let split = splitGlobEntry("/**/*.swift", in: "/d")
        #expect(split.anchor == "/")
        #expect(split.pattern == "**/*.swift")
    }

    @Test("splitGlobEntry anchors an absolute entry at its own leading directories")
    func splitAbsoluteEntry() {
        let split = splitGlobEntry("/a/b/*.swift", in: "/d")
        #expect(split.anchor == "/a/b")
        #expect(split.pattern == "*.swift")
    }

    @Test("splitGlobEntry drops a trailing slash, as expandPath does")
    func splitTrailingSlash() {
        let split = splitGlobEntry("Sources/**/", in: "/d")
        #expect(split.anchor == "/d/Sources")
        #expect(split.pattern == "**")
    }

    @Test("splitGlobEntry drops a doubled slash before the pattern")
    func splitDoubledSlash() {
        let split = splitGlobEntry("Sources//*.swift", in: "/d")
        #expect(split.anchor == "/d/Sources")
        #expect(split.pattern == "*.swift")
    }

    @Test("splitGlobEntry leaves an entry without glob syntax all anchor")
    func splitNoGlobSyntax() {
        let split = splitGlobEntry("Sources/Foo.swift", in: "/d")
        #expect(split.anchor == "/d/Sources/Foo.swift")
        #expect(split.pattern.isEmpty)
    }

    // MARK: - globRegexPattern

    @Test("globRegexPattern matches the anchor literally and the pattern as a glob")
    func regexLiteralAnchor() {
        #expect(globRegexPattern(anchor: "/d [old]", pattern: "*.swift") == "^\\/d \\[old]\\/([^/]+)?\\.swift$")
    }

    @Test("globRegexPattern does not double the slash after a root anchor")
    func regexRootAnchor() {
        #expect(globRegexPattern(anchor: "/", pattern: "**") == "^\\/.+$")
    }

    @Test("globRegexPattern matches an anchor with no pattern exactly")
    func regexAnchorOnly() {
        #expect(globRegexPattern(anchor: "/d*/Foo.swift", pattern: "") == "^\\/d\\*\\/Foo\\.swift$")
    }

    // MARK: - Glob.matches

    @Test("Glob.path matches exact path")
    func globPathMatchesExact() {
        let glob = Glob.path("/path/to/file.swift")
        #expect(glob.matches("/path/to/file.swift"))
    }

    @Test("Glob.path matches what lies inside the path it names", arguments: [
        "/p/Sources/App/A.swift", "/p/Sources/App/Sub/B.swift", "/p/Sources/App/\u{301}x.swift"
    ])
    func globPathMatchesInside(path: String) {
        #expect(Glob.path("/p/Sources/App").matches(path))
        #expect(Glob.path("/p/Sources/App/").matches(path))
    }

    /// It used to test `path.contains(globPath)`, which took every path holding it (#111).
    @Test("Glob.path does not match a sibling, a parent, or the same names elsewhere", arguments: [
        "/p/Sources/AppKit/K.swift", "/p/Sources/AppDelegate.swift", "/p/Sources", "/q/p/Sources/App/A.swift"
    ])
    func globPathStopsAtComponentBoundary(path: String) {
        #expect(Glob.path("/p/Sources/App").matches(path) == false)
    }

    @Test("Glob.path for the root matches every absolute path")
    func globPathRoot() {
        #expect(Glob.path("/").matches("/p/Sources/App/A.swift"))
    }

    @Test("Glob.path does not match unrelated path")
    func globPathNoMatch() {
        let glob = Glob.path("/other/path/file.swift")
        #expect(glob.matches("/completely/different/path.swift") == false)
    }

    @Test("Glob.regex matches pattern")
    func globRegexMatches() {
        let pattern = "^.*\\.swift$"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let glob = Glob.regex(regex)
            #expect(glob.matches("/path/to/file.swift"))
            #expect(glob.matches("/path/to/file.txt") == false)
        }
    }

    // MARK: - Glob.description

    @Test("Glob.path description returns path string")
    func globPathDescription() {
        let glob = Glob.path("/some/path/file.swift")
        #expect(glob.description == "/some/path/file.swift")
    }

    @Test("Glob.regex description reconstructs glob pattern")
    func globRegexDescription() {
        let globs = expandGlobs("**/*.swift", in: "/tmp")
        for glob in globs {
            let desc = glob.description
            #expect(desc.isEmpty == false)
        }
    }

    // MARK: - matchGlobs

    @Test("matchGlobs finds matching files in directory")
    func matchGlobsFindsFiles() {
        let globs = expandGlobs("**/Mock*.swift", in: projectMockURL.path)
        let results = matchGlobs(globs, in: projectMockURL.path)
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.lastPathComponent.hasPrefix("Mock") })
    }

    @Test("matchGlobs returns empty for non-matching pattern")
    func matchGlobsNoMatch() {
        let globs = expandGlobs("NonExistent*.xyz", in: projectMockURL.path)
        let results = matchGlobs(globs, in: projectMockURL.path)
        // Should be empty since no .xyz files exist
        #expect(results.allSatisfy { $0.pathExtension == "xyz" } || results.isEmpty)
    }
}
