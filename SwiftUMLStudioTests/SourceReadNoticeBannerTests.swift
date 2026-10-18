import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

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

/// The view model keeps the notices about the selection, and the preview shows them.
///
/// Serialized, because generating drains the framework's process-wide `SourceReadNotices`.
@Suite("Source read notices in the view model", .serialized)
@MainActor
struct SourceReadNoticeViewModelTests {
    private func notice(_ path: String) -> String {
        "\(path):2:25: a `[` nested more than 10 deep in other `[`."
    }

    private func makeViewModel(selecting paths: [String]) -> DiagramViewModel {
        let viewModel = DiagramViewModel(persistenceController: .init(inMemory: true))
        viewModel.selectedPaths = paths
        return viewModel
    }

    @Test("notices about a selected file, or one in a selected folder, are kept once each")
    func keepsSelected() {
        let viewModel = makeViewModel(selecting: ["/p/Sources", "/q/Only.swift"])
        viewModel.collectSourceReadNotices([
            notice("/p/Sources/Deep.swift"), notice("/q/Only.swift"), notice("/p/Sources/Deep.swift")
        ])
        #expect(viewModel.sourceReadNotices == [notice("/p/Sources/Deep.swift"), notice("/q/Only.swift")])
    }

    @Test("notices about files outside the selection are dropped")
    func dropsOthers() {
        let viewModel = makeViewModel(selecting: ["/p/Sources"])
        viewModel.collectSourceReadNotices([
            notice("/p/SourcesExtra/Deep.swift"), notice("/elsewhere/Deep.swift"), "no place here"
        ])
        #expect(viewModel.sourceReadNotices.isEmpty)
    }

    /// The temporary directory is under `/var`, a symlink to `/private/var`. Both spellings are
    /// resolved, so a selection written one way matches a notice written the other.
    @Test("a path through a symlink matches the resolved one")
    func symlink() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("studio-notice-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "".write(to: directory.appendingPathComponent("Deep.swift"), atomically: true, encoding: .utf8)
        let plain = directory.path
        let privatePath = plain.hasPrefix("/private/") ? plain : "/private" + plain
        let viewModel = makeViewModel(selecting: [plain])
        viewModel.collectSourceReadNotices([notice(privatePath + "/Deep.swift")])
        #expect(viewModel.sourceReadNotices.count == 1)
    }

    /// Module mode, as it reads each file with SwiftParser only.
    @Test("generating a deep file fills the notices; generating again clears them first")
    func generation() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("studio-nested-brackets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Deep.swift")
        let chain = String(repeating: "[", count: 30) + "1" + String(repeating: "]", count: 30)
        try "import Foundation\nlet x = \(chain)\n".write(to: file, atomically: true, encoding: .utf8)

        _ = SourceReadNotices.drain()
        let viewModel = makeViewModel(selecting: [directory.path])
        viewModel.diagramMode = .dependencyGraph
        viewModel.depsMode = .modules
        viewModel.generate()
        await viewModel.currentTask?.value
        #expect(viewModel.sourceReadNotices.count == 1)
        #expect(viewModel.sourceReadNotices.first.flatMap(SourceReadNoticeBanner.Place.init(notice:))?.line == 2)

        try "import Foundation\nlet x = [[1]]\n".write(to: file, atomically: true, encoding: .utf8)
        viewModel.generate()
        #expect(viewModel.sourceReadNotices.isEmpty)
        await viewModel.currentTask?.value
        #expect(viewModel.sourceReadNotices.isEmpty)
    }

    @Test("the preview shows the banner when there are notices, and not while generating")
    func preview() throws {
        let viewModel = makeViewModel(selecting: ["/p"])
        viewModel.sourceReadNotices = [notice("/p/Deep.swift")]
        _ = try DiagramPreviewView(viewModel: viewModel).inspect()
            .find(viewWithAccessibilityIdentifier: "sourceReadNoticeBanner")
        viewModel.isGenerating = true
        #expect(throws: InspectionError.self) {
            try DiagramPreviewView(viewModel: viewModel).inspect()
                .find(viewWithAccessibilityIdentifier: "sourceReadNoticeBanner")
        }
    }
}
