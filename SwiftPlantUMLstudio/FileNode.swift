//
//  FileNode.swift
//  SwiftPlantUMLstudio
//
//  Created by joe cursio on 3/11/26.
//

import Foundation

struct FileNode: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url
    }

    /// Build a file tree from a flat list of paths (files and/or directories).
    /// Only `.swift` files are included; empty directories are pruned.
    static func buildTree(from paths: [String]) -> [FileNode] {
        let fileManager = FileManager.default
        var swiftURLs: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                collectSwiftFiles(in: url, fileManager: fileManager, into: &swiftURLs)
            } else if url.pathExtension == "swift" {
                swiftURLs.append(url)
            }
        }

        guard !swiftURLs.isEmpty else { return [] }

        let commonPrefix = longestCommonDirectory(of: swiftURLs)
        return buildNodes(from: swiftURLs, relativeTo: commonPrefix)
    }

    /// Recursively find all `.swift` files under a directory.
    private static func collectSwiftFiles(
        in directory: URL,
        fileManager: FileManager,
        into results: inout [URL]
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            results.append(fileURL)
        }
    }

    /// Find the longest common directory prefix among a set of file URLs.
    private static func longestCommonDirectory(of urls: [URL]) -> URL {
        guard let first = urls.first else { return URL(fileURLWithPath: "/") }

        var commonComponents = first.deletingLastPathComponent().pathComponents
        for url in urls.dropFirst() {
            let dirComponents = url.deletingLastPathComponent().pathComponents
            let minCount = min(commonComponents.count, dirComponents.count)
            let matchCount = zip(commonComponents.prefix(minCount), dirComponents.prefix(minCount))
                .prefix(while: { $0 == $1 })
                .count
            commonComponents = Array(commonComponents.prefix(matchCount))
        }

        if commonComponents.isEmpty {
            return URL(fileURLWithPath: "/")
        }

        var path = commonComponents.joined(separator: "/")
        // pathComponents splits "/" into ["/"], so joined gives "//..." — fix that
        if path.hasPrefix("//") {
            path = String(path.dropFirst())
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private struct Entry {
        let url: URL
        let relativeComponents: [String]
    }

    /// Build a nested tree of FileNodes from flat file URLs, relative to a base directory.
    private static func buildNodes(from urls: [URL], relativeTo base: URL) -> [FileNode] {
        let baseComponents = base.pathComponents
        let entries: [Entry] = urls.map { url in
            let components = url.pathComponents
            let relative = Array(components.dropFirst(baseComponents.count))
            return Entry(url: url, relativeComponents: relative)
        }

        return buildLevel(entries: entries, depth: 0, basePath: base)
    }

    private static func buildLevel(entries: [Entry], depth: Int, basePath: URL) -> [FileNode] {
        // Group entries by the component at the current depth
        var groups: [String: [Entry]] = [:]
        for entry in entries {
            guard depth < entry.relativeComponents.count else { continue }
            let key = entry.relativeComponents[depth]
            groups[key, default: []].append(entry)
        }

        var nodes: [FileNode] = []
        for (name, groupEntries) in groups {
            let dirURL = basePath.appendingPathComponent(name, isDirectory: true)

            // Leaf files: entries where this is the last component
            let leaves = groupEntries.filter { $0.relativeComponents.count == depth + 1 }
            // Subtree entries: entries with more components
            let deeper = groupEntries.filter { $0.relativeComponents.count > depth + 1 }

            if !deeper.isEmpty {
                // This is a directory
                let childNodes = buildLevel(entries: deeper, depth: depth + 1, basePath: dirURL)
                let leafNodes = leaves.map { entry in
                    FileNode(id: entry.url, name: entry.url.lastPathComponent,
                             url: entry.url, isDirectory: false, children: nil)
                }
                // If the directory has only subdirectory children (no leaf files at this level),
                // just add the child nodes. Otherwise combine.
                let allChildren = (childNodes + leafNodes).sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                nodes.append(FileNode(
                    id: dirURL, name: name, url: dirURL,
                    isDirectory: true, children: allChildren
                ))
            } else {
                // All entries are leaf files
                for entry in leaves {
                    nodes.append(FileNode(
                        id: entry.url, name: name,
                        url: entry.url, isDirectory: false, children: nil
                    ))
                }
            }
        }

        // Sort: directories first, then files, both alphabetically
        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Collect all leaf (non-directory) URLs from a tree.
    static func allLeafURLs(from nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
            if let children = node.children {
                result.append(contentsOf: allLeafURLs(from: children))
            } else {
                result.append(node.url)
            }
        }
        return result
    }
}
