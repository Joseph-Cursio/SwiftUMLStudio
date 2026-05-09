import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

@Suite("CoreDataModelExtractor")
struct CoreDataModelExtractorTests {

    /// `TestFixtures/SampleProject/CoreData/` lives at the repo root —
    /// walk up five levels from this file to reach it.
    private func bundleURL(_ name: String) -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()  // ParsingTests
            .deletingLastPathComponent()  // SwiftUMLBridgeFrameworkTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SwiftUMLBridge
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("TestFixtures/SampleProject/CoreData")
            .appendingPathComponent(name)
    }

    // MARK: - Bookstore (canonical positive)

    @Test("Bookstore: extracts Author + Book entities with their attributes")
    func bookstoreEntities() throws {
        let model = try CoreDataModelExtractor.extract(from: bundleURL("Bookstore.xcdatamodeld"))
        #expect(Set(model.entities.map(\.name)) == ["Author", "Book"])

        let author = try #require(model.entities.first { $0.name == "Author" })
        #expect(Set(author.attributes.map(\.name)) == ["name", "birthYear"])
        let birthYear = try #require(author.attributes.first { $0.name == "birthYear" })
        #expect(birthYear.isOptional == true)
        #expect(birthYear.type == "Integer 32")

        let book = try #require(model.entities.first { $0.name == "Book" })
        let title = try #require(book.attributes.first { $0.name == "title" })
        #expect(title.isOptional == false)
        #expect(title.type == "String")
    }

    @Test("Bookstore: emits a single Author<->Book relationship after dedupe")
    func bookstoreRelationships() throws {
        let model = try CoreDataModelExtractor.extract(from: bundleURL("Bookstore.xcdatamodeld"))
        // Core Data declares both sides; dedupe should leave exactly one edge.
        #expect(model.relationships.count == 1)
        let edge = try #require(model.relationships.first)
        #expect(Set([edge.from, edge.toEntity]) == ["Author", "Book"])
        // The "books" edge points Author → Book with toMany on the destination.
        if edge.from == "Author" {
            #expect(edge.toCardinality == .zeroOrMany || edge.toCardinality == .oneOrMany)
            #expect(edge.fromCardinality == .exactlyOne)
        }
    }

    // MARK: - Versioning

    @Test("Library: .xccurrentversion picks V2 (Loan + Member, not just V1's Loan)")
    func libraryPicksActiveVersion() throws {
        let model = try CoreDataModelExtractor.extract(from: bundleURL("Library.xcdatamodeld"))
        #expect(Set(model.entities.map(\.name)) == ["Loan", "Member"])
        let loan = try #require(model.entities.first { $0.name == "Loan" })
        // returnedDate is V2-only — its presence proves V2 was the active pick.
        #expect(loan.attributes.contains(where: { $0.name == "returnedDate" }))
    }

    @Test("resolveActiveContentsURL prefers .xccurrentversion target")
    func resolveActiveContentsHonoursPlist() throws {
        let url = try CoreDataModelExtractor.resolveActiveContentsURL(
            bundleURL: bundleURL("Library.xcdatamodeld")
        )
        #expect(url.path.contains("V2.xcdatamodel"))
    }

    // MARK: - Inheritance

    @Test("Inheritance: parentEntity surfaces as an 'is a' relationship")
    func inheritanceProducesIsAEdge() throws {
        let model = try CoreDataModelExtractor.extract(from: bundleURL("Inheritance.xcdatamodeld"))
        #expect(Set(model.entities.map(\.name)) == ["Person", "Employee"])
        let isA = try #require(model.relationships.first { $0.label == "is a" })
        #expect(isA.from == "Employee")
        #expect(isA.toEntity == "Person")
    }

    // MARK: - Empty bundle

    @Test("Empty: bundle with zero entities returns an empty ERModel without throwing")
    func emptyBundle() throws {
        let model = try CoreDataModelExtractor.extract(from: bundleURL("Empty.xcdatamodeld"))
        #expect(model.entities.isEmpty)
        #expect(model.relationships.isEmpty)
        #expect(model.isEmpty)
    }

    // MARK: - Error cases

    @Test("missing bundle directory throws noModelVersionFound")
    func missingBundleThrows() {
        let bogus = URL(fileURLWithPath: "/this/path/does/not/exist-\(UUID().uuidString).xcdatamodeld")
        #expect(throws: CoreDataModelExtractor.ExtractionError.self) {
            try CoreDataModelExtractor.extract(from: bogus)
        }
    }
}

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
        #expect(!script.text.isEmpty)
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
