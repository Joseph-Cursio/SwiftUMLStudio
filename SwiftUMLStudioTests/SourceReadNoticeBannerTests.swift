import Foundation
import SwiftUI
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing
import ViewInspector

/// A file with `[` nested past the parsers' limit is drawn with those brackets read as spaces, so
/// the banner is the only sign in Studio that it was not read as written (#148).
@Suite("SourceReadNoticeBanner")
@MainActor
struct SourceReadNoticeBannerTests {
    static let notice = "/Users/me/Grid.swift:2:25: a `[` nested more than 10 deep in other `[`. It and each such "
        + "`[` after it in the file were read as spaces, with their `]`, as each one doubles the time a parse takes"

    @Test("a notice names its file, line and column")
    func place() throws {
        let place = try #require(SourceReadNoticeBanner.Place(notice: Self.notice))
        #expect(place.file == "/Users/me/Grid.swift")
        #expect(place.line == 2 && place.column == 25)
        #expect(place.label == "Grid.swift, line 2, column 25")
    }

    @Test("a path holding a colon is read whole")
    func colonInPath() throws {
        let place = try #require(SourceReadNoticeBanner.Place(notice: "/tmp/a:b/Grid.swift:7:3: a `[`"))
        #expect(place.file == "/tmp/a:b/Grid.swift" && place.line == 7 && place.column == 3)
    }

    @Test("a notice without a place is not shown")
    func noPlace() {
        #expect(SourceReadNoticeBanner.Place(notice: "something else") == nil)
        #expect(SourceReadNoticeBanner.places(for: ["something else"], isGenerating: false) == nil)
    }

    @Test("no banner while generating or with no notices")
    func hidden() {
        #expect(SourceReadNoticeBanner.places(for: [Self.notice], isGenerating: true) == nil)
        #expect(SourceReadNoticeBanner.places(for: [], isGenerating: false) == nil)
        #expect(SourceReadNoticeBanner.places(for: [Self.notice], isGenerating: false)?.count == 1)
    }

    @Test("the text says what was read as spaces and that the rest was read")
    func text() {
        #expect(SourceReadNoticeBanner.headline == "Deeply nested brackets read as spaces")
        #expect(SourceReadNoticeBanner.detail.contains("was read as a space"))
        #expect(SourceReadNoticeBanner.detail.contains("The rest of the file was read"))
    }
}
