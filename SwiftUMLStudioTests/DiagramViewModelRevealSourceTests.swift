import Foundation
import Testing
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

@Suite("DiagramViewModel.revealSource")
@MainActor
struct DiagramViewModelRevealSourceTests {

    private func makeTempSwiftFile(named name: String, content: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("revealSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("revealSource loads the file content and sets the highlighted line")
    func revealSourceLoadsFileAndSetsLine() throws {
        let url = try makeTempSwiftFile(named: "Foo.swift", content: "class Foo {}\nclass Bar {}\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.revealSource(at: SourceLocation(filePath: url.path, line: 2, column: 7))

        #expect(viewModel.selectedFileURL == url)
        #expect(viewModel.selectedFileContent.contains("class Bar"))
        #expect(viewModel.highlightedSourceLine == 2)
    }

    @Test("revealSource is a no-op when filePath is empty")
    func revealSourceIgnoresEmptyPath() {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedFileURL = URL(fileURLWithPath: "/tmp/keep")
        viewModel.highlightedSourceLine = 5

        viewModel.revealSource(at: SourceLocation(filePath: "", line: 10, column: 1))

        #expect(viewModel.selectedFileURL == URL(fileURLWithPath: "/tmp/keep"))
        #expect(viewModel.highlightedSourceLine == 5)
    }

    @Test("manually selecting a different file clears the highlight")
    func selectFileClearsHighlight() throws {
        let url = try makeTempSwiftFile(named: "Foo.swift", content: "// hello\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.revealSource(at: SourceLocation(filePath: url.path, line: 1, column: 1))
        #expect(viewModel.highlightedSourceLine == 1)

        viewModel.selectFile(url)
        #expect(viewModel.highlightedSourceLine == nil)
    }
}
