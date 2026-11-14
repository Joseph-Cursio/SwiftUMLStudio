//  Tests for DiagramMode, FileNode, and MermaidHTMLBuilder.

import Foundation
@testable import SwiftUMLStudio
import Testing

// MARK: - FileNode Tests

@Suite("FileNode") @MainActor
struct FileNodeTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FileNodeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("buildTree returns empty for empty paths")
    func buildTreeEmpty() {
        let tree = FileNode.buildTree(from: [])
        #expect(tree.isEmpty)
    }

    @Test("buildTree returns empty for nonexistent paths")
    func buildTreeNonexistent() {
        let tree = FileNode.buildTree(from: ["/nonexistent/path/file.swift"])
        #expect(tree.isEmpty)
    }

    @Test("buildTree returns single file")
    func buildTreeSingleFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Hello.swift")
        try "struct Hello {}".write(to: file, atomically: true, encoding: .utf8)

        let tree = FileNode.buildTree(from: [file.path()])
        #expect(tree.count == 1)
        #expect(tree[0].name == "Hello.swift")
        #expect(tree[0].isDirectory == false)
        #expect(tree[0].children == nil)
    }

    @Test("buildTree filters out non-swift files in directories")
    func buildTreeFiltersNonSwift() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "not swift".write(to: dir.appending(path: "readme.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appending(path: "config.json"), atomically: true, encoding: .utf8)

        let tree = FileNode.buildTree(from: [dir.path()])
        let allURLs = FileNode.allLeafURLs(from: tree)
        #expect(allURLs.count == 1)
        #expect(allURLs[0].lastPathComponent == "A.swift")
    }

    @Test("buildTree creates directory nodes for nested structures")
    func buildTreeNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)

        let tree = FileNode.buildTree(from: [dir.path()])
        #expect(tree.count == 2) // Models/ directory + App.swift
        let dirNode = tree.first(where: \.isDirectory)
        #expect(dirNode?.name == "Models")
        #expect(dirNode?.children?.count == 1)
        #expect(dirNode?.children?[0].name == "Model.swift")
    }

    @Test("allLeafURLs collects all file URLs from nested tree")
    func allLeafURLsNested() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appending(path: "Sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: subdir.appending(path: "B.swift"), atomically: true, encoding: .utf8)

        let tree = FileNode.buildTree(from: [dir.path()])
        let urls = FileNode.allLeafURLs(from: tree)
        #expect(urls.count == 2)
    }
}
