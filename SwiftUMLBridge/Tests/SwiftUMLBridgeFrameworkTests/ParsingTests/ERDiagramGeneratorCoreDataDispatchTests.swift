import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ERDiagramGenerator dispatches .xcdatamodeld to CoreDataModelExtractor")
struct ERDiagramGeneratorCoreDataDispatchTests {

    private func bundlePath(_ name: String) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/SampleProject/CoreData")
            .appendingPathComponent(name)
            .path
    }

    @Test("generateScript with a .xcdatamodeld path produces non-empty script")
    func dispatchToCoreData() throws {
        let path = bundlePath("Bookstore.xcdatamodeld")
        let script = ERDiagramGenerator().generateScript(for: [path], with: .default)
        #expect(script.text.isEmpty == false)
        #expect(script.text.contains("Author"))
        #expect(script.text.contains("Book"))
    }

    @Test("generateScript renders Mermaid erDiagram for Core Data input")
    func mermaidForCoreData() throws {
        let path = bundlePath("Bookstore.xcdatamodeld")
        var configuration = Configuration.default
        configuration.format = .mermaid
        let script = ERDiagramGenerator().generateScript(for: [path], with: configuration)
        #expect(script.text.contains("erDiagram"))
        #expect(script.text.contains("Author"))
        #expect(script.text.contains("Book"))
    }
}
