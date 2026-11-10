//  Integration tests for diagram generation and file browser features.

import Foundation
import SwiftData
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

// MARK: - DiagramViewModel FileBrowser Tests

@Suite("DiagramViewModel FileBrowser") @MainActor
struct DiagramViewModelFileBrowserTests {

    @Test("rebuildFileTree populates fileTree from selectedPaths")
    func rebuildFileTreePopulates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct Foo {}".write(to: dir.appending(path: "Foo.swift"), atomically: true, encoding: .utf8)

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.selectedPaths = [dir.path()]
        viewModel.rebuildFileTree()
        #expect(viewModel.fileTree.isEmpty == false)
    }

    @Test("rebuildFileTree auto-selects first file")
    func rebuildFileTreeAutoSelects() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "struct A {}".write(to: dir.appending(path: "A.swift"), atomically: true, encoding: .utf8)

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.selectedPaths = [dir.path()]
        viewModel.rebuildFileTree()
        #expect(viewModel.selectedFileURL != nil)
        #expect(viewModel.selectedFileContent.isEmpty == false)
    }

    @Test("selectFile loads content")
    func selectFileLoadsContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Test.swift")
        try "struct Test {}".write(to: file, atomically: true, encoding: .utf8)

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.selectFile(file)
        #expect(viewModel.selectedFileContent == "struct Test {}")
        #expect(viewModel.selectedFileURL == file)
    }

    @Test("selectFile with nil clears content")
    func selectFileNilClears() {
        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.selectedFileContent = "old content"
        viewModel.selectFile(nil)
        #expect(viewModel.selectedFileContent.isEmpty)
        #expect(viewModel.selectedFileURL == nil)
    }

    @Test("rebuildFileTree clears selection when file no longer in paths")
    func rebuildFileTreeClearsStaleSelection() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "VMFileBrowser-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "Gone.swift")
        try "struct Gone {}".write(to: file, atomically: true, encoding: .utf8)

        let viewModel = DiagramViewModel(persistenceController: PersistenceController(inMemory: true))
        viewModel.selectedPaths = [dir.path()]
        viewModel.rebuildFileTree()
        #expect(viewModel.selectedFileURL != nil)

        // Remove the file and rebuild with empty paths
        viewModel.selectedPaths = []
        viewModel.rebuildFileTree()
        #expect(viewModel.selectedFileURL == nil)
        #expect(viewModel.selectedFileContent.isEmpty)
    }
}
