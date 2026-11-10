//
//  SelectionPathSpellingTests.swift
//  SwiftUMLStudioTests
//
//  A selected path is a file system path, not a URL's percent-encoded path: the Bridge reads it
//  literally, so `My%20Project` is a folder that does not exist and the diagram comes out empty.
//

import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@MainActor
@Suite("A selected path is spelled as it is on disk")
struct SelectionPathSpellingTests {

    /// `50%20off` is a folder really named that: it must not be decoded into `50 off`.
    nonisolated private static let folderNames = [
        "Plain", "My Project", "caf\u{E9}", "C# Tools", "100% done", "50%20off"
    ]

    private func makeFolder(named name: String) throws -> (root: URL, folder: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectionPathSpelling-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
            class Orchestrator {
                func run() {
                    helper.process()
                }
                let helper = Helper()
            }
            class Helper {
                func process() {}
            }
            """.write(to: folder.appendingPathComponent("Fixture.swift"), atomically: true, encoding: .utf8)
        return (root, folder)
    }

    private func makeViewModel() -> DiagramViewModel {
        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.diagramMode = .sequenceDiagram
        viewModel.diagramFormat = .plantuml
        viewModel.entryPoint = "Orchestrator.run"
        return viewModel
    }

    @Test("a picked folder is found and its calls are drawn", arguments: folderNames)
    func pickedFolderGenerates(name: String) async throws {
        let (root, folder) = try makeFolder(named: name)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel()

        viewModel.applySelection(urls: [folder])

        let path = try #require(viewModel.selectedPaths.first)
        #expect(FileManager.default.fileExists(atPath: path), "\(path)")
        #expect(!FileNode.buildTree(from: viewModel.selectedPaths).isEmpty, "\(path)")
        viewModel.generate()
        await viewModel.currentTask?.value
        let script = try #require(viewModel.currentScript)
        #expect(script.text.contains("process"), "\(script.text)")
    }

    @Test("a folder restored from its bookmark is found and its calls are drawn", arguments: folderNames)
    func restoredFolderGenerates(name: String) async throws {
        let (root, folder) = try makeFolder(named: name)
        defer { try? FileManager.default.removeItem(at: root) }
        let bookmark = try #require(SecurityScopedURL.makeBookmark(for: folder))
        let entity = DiagramEntity()
        entity.identifier = UUID()
        entity.timestamp = Date()
        entity.mode = DiagramMode.sequenceDiagram.rawValue
        entity.format = DiagramFormat.plantuml.rawValue
        entity.entryPoint = "Orchestrator.run"
        entity.sequenceDepth = 3
        entity.paths = try JSONEncoder().encode(["/tmp/stale-fallback"])
        entity.pathBookmarks = try JSONEncoder().encode([Data?.some(bookmark)])
        let viewModel = makeViewModel()

        viewModel.loadDiagram(entity)

        let path = try #require(viewModel.selectedPaths.first)
        #expect(FileManager.default.fileExists(atPath: path), "\(path)")
        viewModel.generate()
        await viewModel.currentTask?.value
        let script = try #require(viewModel.currentScript)
        #expect(script.text.contains("process"), "\(script.text)")
    }

    /// A snapshot is matched to a selection by these strings (`SnapshotManager.latestSnapshot`), so
    /// a path with nothing to encode must keep its spelling, trailing slash included.
    @Test("a path with nothing to encode keeps the spelling saved snapshots matched")
    func plainPathKeepsItsSpelling() throws {
        let (root, folder) = try makeFolder(named: "Plain")
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = makeViewModel()
        viewModel.applySelection(urls: [folder])
        #expect(viewModel.selectedPaths == [folder.path()])
    }
}
