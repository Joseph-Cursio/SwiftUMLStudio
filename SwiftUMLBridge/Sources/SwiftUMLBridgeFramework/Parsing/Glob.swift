import Foundation

//
//  Globs.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 31/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

func pathContainsGlobSyntax(_ path: String) -> Bool {
    "*?[{".contains(where: { path.contains($0) })
}

/// Glob type represents either an exact path or wildcard
internal enum Glob: CustomStringConvertible {
    case path(String)
    case regex(NSRegularExpression)

    internal func matches(_ path: String) -> Bool {
        switch self {
        case let .path(globPath):
            return globPath == path || path.contains(globPath)
        case let .regex(regex):
            let range = NSRange(location: 0, length: path.utf16.count)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        }
    }

    internal var description: String {
        switch self {
        case let .path(path):
            return path
        case let .regex(regex):
            var result = regex.pattern.dropFirst().dropLast()
                .replacingOccurrences(of: "([^/]+)?", with: "*")
                .replacingOccurrences(of: "(.+/)?", with: "**/")
                .replacingOccurrences(of: ".+", with: "**")
                .replacingOccurrences(of: "[^/]", with: "?")
                .replacingOccurrences(of: "\\", with: "")
            while let range = result.range(of: "\\([^)]+\\)", options: .regularExpression) {
                let options = result[range].dropFirst().dropLast().components(separatedBy: "|")
                result.replaceSubrange(range, with: "{\(options.joined(separator: ","))}")
            }
            return result
        }
    }
}

// Parse a comma-delimited list of items
func parseCommaDelimitedList(_ string: String) -> [String] {
    string.components(separatedBy: ",").compactMap {
        let item = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }
}

internal func expandPath(_ path: String, in directory: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    if path.hasPrefix("~") {
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    return URL(fileURLWithPath: directory).appendingPathComponent(path)
}

/// `path` as directory enumeration spells it: its real path, with every
/// symlink resolved, as `realpath(3)` gives it. `FileManager` reports a walked
/// directory's entries under that path: a walk started at `/tmp/x` yields
/// `/private/tmp/x/…`. `standardizingPath` and `resolvingSymlinksInPath()`
/// strip `/private` again, and `canonicalPathKey` leaves a final symlink
/// unresolved — a search directory can be one — so none of them will do.
/// The result is spelled as `URL.path` spells it, as every path matched against
/// a glob is: `realpath` returns names as stored, and one made by `mkdir` in a
/// shell or by a git checkout is stored composed, which `URL` decomposes.
/// A path that does not exist is returned unchanged.
internal func canonicalPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved)).path
}

/// `url`'s path in the form directory enumeration reports it: the parent goes
/// through `canonicalPath`, and the file keeps its own name, so a file that is
/// itself a symlink matches by that name, as it does when enumerated.
internal func enumeratedPath(of url: URL) -> String {
    let parent = canonicalPath(url.deletingLastPathComponent().path)
    return URL(fileURLWithPath: parent).appendingPathComponent(url.lastPathComponent).path
}

/// `path`, an include or exclude entry taken as written, with no glob expansion,
/// and expanded to an absolute path, in the form directory enumeration reports
/// what it names. A directory goes through `canonicalPath`, as a walk started
/// there reports its files; anything else goes through `enumeratedPath(of:)`,
/// keeping its name.
internal func enumeratedPath(ofEntry path: String) -> String {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
        return canonicalPath(path)
    }
    return enumeratedPath(of: URL(fileURLWithPath: path))
}

/// `entry`, an include or exclude entry, expanded to an absolute path and split
/// at its first component with glob syntax. The `anchor` is the directory the
/// components before it name, in the form directory enumeration reports it:
/// through `canonicalPath`, since resolving the search directory is not enough —
/// an absolute or `~` entry never uses it, and a relative entry can run through
/// a symlink below it. The `pattern` is the rest, as `expandPath` spells it.
/// Only the entry is searched for glob syntax: a relative entry's search
/// directory is a literal path however it is named, so it is always anchor.
/// A `{…}` group is glob syntax too, though by now it is a `<<<n>>>` token. An
/// entry with no glob syntax is all anchor, by `enumeratedPath(ofEntry:)`.
internal func splitGlobEntry(_ entry: String, in directory: String) -> (anchor: String, pattern: String) {
    let path = expandPath(entry, in: directory).path
    let components = entry.components(separatedBy: "/")
    guard let patternStart = components.firstIndex(where: { pathContainsGlobSyntax($0) || $0.contains("<<<") })
    else {
        return (enumeratedPath(ofEntry: path), "")
    }
    let leading = components[..<patternStart].joined(separator: "/")
    let anchor = leading.isEmpty && entry.hasPrefix("/") ? "/" : expandPath(leading, in: directory).path
    let prefix = anchor.hasSuffix("/") ? anchor : anchor + "/"
    // Not expected, but should expansion not keep the anchor, read it all as a glob.
    guard path.hasPrefix(prefix) else { return ("/", String(path.dropFirst())) }
    // A doubled slash before the pattern, as in `Sources//*.swift`, names no directory.
    return (canonicalPath(anchor), String(path.dropFirst(prefix.count).drop { $0 == "/" }))
}

/// The anchored regex for an entry split by `splitGlobEntry`, with each
/// `<<<n>>>` token in `pattern` replaced by its alternation from `tokens`. The
/// anchor is a literal path, so it is escaped whole: read as glob syntax, a
/// directory named `Proj [old]` became a character class that never matched
/// it, and a `*` or `?` in a directory name matched its siblings as well.
internal func globRegexPattern(anchor: String, pattern: String, tokens: [String: String] = [:]) -> String {
    guard !pattern.isEmpty else {
        return "^\(NSRegularExpression.escapedPattern(for: anchor))$"
    }
    var patternRegex = String(pattern.globPatternToRegex().dropFirst())
    for (token, replacement) in tokens {
        patternRegex = patternRegex.replacingOccurrences(of: token, with: replacement)
    }
    let directory = anchor.hasSuffix("/") ? anchor : anchor + "/"
    return "^" + NSRegularExpression.escapedPattern(for: directory) + patternRegex
}

/// Expand one or more comma-delimited file paths using glob syntax
internal func expandGlobs(_ paths: String, in directory: String) -> [Glob] {
    // Each entry is anchored where enumeration will report its files, by
    // `enumeratedPath(ofEntry:)` or `splitGlobEntry(_:in:)`, which resolve
    // the search directory along with the rest of the entry's directories.
    guard pathContainsGlobSyntax(paths) else {
        return parseCommaDelimitedList(paths).map {
            .path(enumeratedPath(ofEntry: expandPath($0, in: directory).path))
        }
    }
    var paths = paths
    var tokens = [String: String]()
    while let range = paths.range(of: "\\{[^}]+\\}", options: .regularExpression) {
        let options = paths[range].dropFirst().dropLast()
            .replacingOccurrences(of: "[.+(){\\\\|]", with: "\\\\$0", options: .regularExpression)
            .components(separatedBy: ",")
        let token = "<<<\(tokens.count)>>>"
        tokens[token] = "(\(options.joined(separator: "|")))"
        paths.replaceSubrange(range, with: token)
    }
    return parseCommaDelimitedList(paths).map { entry -> Glob in
        let path = expandPath(entry, in: directory).path
        if FileManager.default.fileExists(atPath: path) {
            return .path(enumeratedPath(ofEntry: path))
        }
        let (anchor, pattern) = splitGlobEntry(entry, in: directory)
        let regex = globRegexPattern(anchor: anchor, pattern: pattern, tokens: tokens)
        do {
            return try .regex(NSRegularExpression(pattern: regex, options: []))
        } catch {
            BridgeLogger.shared.error("failed to compile glob regex '\(regex)': \(error)")
            return .path(path)
        }
    }
}

func matchGlobs(_ globs: [Glob], in directory: String) -> [URL] {
    var urls = [URL]()
    let keys: [URLResourceKey] = [.isDirectoryKey]
    let manager = FileManager.default
    func enumerate(_ directory: URL) {
        guard let files = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: []
        ) else {
            return
        }
        for url in files {
            let path = url.path
            var isDirectory: ObjCBool = false
            if globs.contains(where: { $0.matches(path) }) {
                urls.append(url)
            } else {
                let exists = manager.fileExists(atPath: path, isDirectory: &isDirectory)
                if exists, isDirectory.boolValue {
                    enumerate(url)
                }
            }
        }
    }
    // Listing a symlink to a directory yields nothing, so list where it leads.
    // A symlinked parent needs no help: its listing is reported resolved.
    enumerate(URL(fileURLWithPath: canonicalPath(directory)))
    return urls
}
