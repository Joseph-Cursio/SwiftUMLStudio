@testable import SwiftUMLBridgeFramework
import Testing

@Suite("FileOptions")
struct FileOptionsTests {

    @Test("description is 'no values' when both are empty")
    func bothEmptyDescription() {
        let opts = FileOptions(include: [], exclude: [])
        #expect(opts.description == "no values")
    }

    @Test("description shows only exclude when include is empty")
    func excludeOnlyDescription() {
        let opts = FileOptions(include: [], exclude: ["Tests/**"])
        #expect(opts.description == "exclude: Tests/**")
    }

    @Test("description shows only include when exclude is empty")
    func includeOnlyDescription() {
        let opts = FileOptions(include: ["Sources/**"], exclude: [])
        #expect(opts.description == "include: Sources/**")
    }

    @Test("description shows both when both are non-empty")
    func bothNonEmptyDescription() {
        let opts = FileOptions(include: ["Sources/**"], exclude: ["Tests/**"])
        let desc = opts.description
        #expect(desc.contains("include: Sources/**"))
        #expect(desc.contains("exclude: Tests/**"))
        #expect(desc.contains("&&"))
    }

    @Test("description uses nil include as empty")
    func nilIncludeDescription() {
        let opts = FileOptions(include: nil, exclude: ["Tests/**"])
        #expect(opts.description == "exclude: Tests/**")
    }

    @Test("description uses nil exclude as empty")
    func nilExcludeDescription() {
        let opts = FileOptions(include: ["Sources/**"], exclude: nil)
        #expect(opts.description == "include: Sources/**")
    }

    @Test("description joins multiple include patterns with comma")
    func multipleIncludePatterns() {
        let opts = FileOptions(include: ["Sources/**", "Lib/**"], exclude: [])
        #expect(opts.description.contains("Sources/**"))
        #expect(opts.description.contains("Lib/**"))
    }
}
