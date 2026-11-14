import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

@Suite("DiagramViewModel ER generation with .xcdatamodeld input")
@MainActor
struct DiagramViewModelCoreDataTests {

    /// Build a minimal Bookstore .xcdatamodeld in a temp directory the
    /// sandboxed test bundle can reach. Returns the bundle URL and the
    /// parent root URL for cleanup.
    private func makeBookstoreBundle() throws -> (bundleURL: URL, root: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("studio-coredata-\(UUID().uuidString)", isDirectory: true)
        let modelDir = root
            .appendingPathComponent("Bookstore.xcdatamodeld/Bookstore.xcdatamodel", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <model type="com.apple.IDECoreDataModeler.DataModel">
            <entity name="Author" representedClassName="Author" syncable="YES">
                <attribute name="name" optional="NO" attributeType="String"/>
            </entity>
            <entity name="Book" representedClassName="Book" syncable="YES">
                <attribute name="title" optional="NO" attributeType="String"/>
            </entity>
        </model>
        """
        try xml.write(
            to: modelDir.appendingPathComponent("contents"),
            atomically: true, encoding: .utf8
        )
        return (root.appendingPathComponent("Bookstore.xcdatamodeld"), root)
    }

    @Test("ERDiagramGenerator dispatches a .xcdatamodeld path to the Core Data extractor")
    func generatorDispatchToCoreData() throws {
        let (bundleURL, root) = try makeBookstoreBundle()
        defer { try? FileManager.default.removeItem(at: root) }

        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ERDiagramGenerator().generateScript(
            for: [bundleURL.path], with: configuration
        )
        #expect(script.text.contains("erDiagram"))
        #expect(script.text.contains("Author"))
        #expect(script.text.contains("Book"))
    }

    @Test("ER mode + .xcdatamodeld path produces a script with the bundle's entities")
    func erWithCoreDataInput() async throws {
        let (bundleURL, root) = try makeBookstoreBundle()
        defer { try? FileManager.default.removeItem(at: root) }

        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.diagramMode = .erDiagram
        viewModel.diagramFormat = .mermaid
        viewModel.selectedPaths = [bundleURL.path]

        await viewModel.generateERDiagram()

        let script = try #require(viewModel.erScript)
        #expect(script.text.contains("erDiagram"))
        #expect(script.text.contains("Author"))
        #expect(script.text.contains("Book"))
    }
}
