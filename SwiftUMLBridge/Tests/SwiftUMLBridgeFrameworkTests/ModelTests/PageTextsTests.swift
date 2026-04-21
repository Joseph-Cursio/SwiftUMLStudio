import Testing
@testable import SwiftUMLBridgeFramework

@Suite("PageTexts")
struct PageTextsTests {

    @Test("plantuml() returns nil when all fields are nil")
    func allNilReturnsNil() {
        let texts = PageTexts()
        #expect(texts.plantuml() == nil)
    }

    @Test("plantuml() returns non-nil when header is set")
    func headerOnlyReturnsNonNil() {
        let texts = PageTexts(header: "Top")
        #expect(texts.plantuml() != nil)
    }

    @Test("plantuml() includes header keyword and content")
    func headerSection() throws {
        let texts = PageTexts(header: "My Header")
        let result = try #require(texts.plantuml())
        #expect(result.contains("header"))
        #expect(result.contains("My Header"))
        #expect(result.contains("end header"))
    }

    @Test("plantuml() includes title keyword and content")
    func titleSection() throws {
        let texts = PageTexts(title: "My Title")
        let result = try #require(texts.plantuml())
        #expect(result.contains("title"))
        #expect(result.contains("My Title"))
        #expect(result.contains("end title"))
    }

    @Test("plantuml() includes legend keyword and content")
    func legendSection() throws {
        let texts = PageTexts(legend: "My Legend")
        let result = try #require(texts.plantuml())
        #expect(result.contains("legend"))
        #expect(result.contains("My Legend"))
        #expect(result.contains("end legend"))
    }

    @Test("plantuml() includes caption keyword and content")
    func captionSection() throws {
        let texts = PageTexts(caption: "My Caption")
        let result = try #require(texts.plantuml())
        #expect(result.contains("caption"))
        #expect(result.contains("My Caption"))
        #expect(result.contains("end caption"))
    }

    @Test("plantuml() includes footer keyword and content")
    func footerSection() throws {
        let texts = PageTexts(footer: "My Footer")
        let result = try #require(texts.plantuml())
        #expect(result.contains("footer"))
        #expect(result.contains("My Footer"))
        #expect(result.contains("end footer"))
    }

    @Test("plantuml() includes all five sections when all fields are set")
    func allFieldsIncluded() throws {
        let texts = PageTexts(header: "H", title: "T", legend: "L", caption: "C", footer: "F")
        let result = try #require(texts.plantuml())
        #expect(result.contains("header"))
        #expect(result.contains("title"))
        #expect(result.contains("legend"))
        #expect(result.contains("caption"))
        #expect(result.contains("footer"))
        #expect(result.contains("end header"))
        #expect(result.contains("end title"))
        #expect(result.contains("end legend"))
        #expect(result.contains("end caption"))
        #expect(result.contains("end footer"))
    }

    @Test("PageTexts respects field mutability")
    func fieldsAreMutable() throws {
        var texts = PageTexts()
        texts.header = "New Header"
        texts.footer = "New Footer"
        let result = try #require(texts.plantuml())
        #expect(result.contains("New Header"))
        #expect(result.contains("New Footer"))
    }
}
