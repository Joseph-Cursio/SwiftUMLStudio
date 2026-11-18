import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing
import ViewInspector

/// The view model keeps the notices about the selection, and the preview shows them. Each
/// generation collects its own (`SourceReadNotices.collector`), so these tests need not run alone.
@Suite("Source read notices in the view model")
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

    /// Two windows, each with a file of its own and one they share. Generating drained the
    /// process-wide list, so the window that finished first took both windows' notices and kept its
    /// own, and the list's one copy of the shared file's notice reached one window only.
    @Test("two windows generating at once each show their own notices")
    func concurrentWindows() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("studio-notice-windows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let chain = String(repeating: "[", count: 30) + "1" + String(repeating: "]", count: 30)
        let source = "import Foundation\nlet x = \(chain)\n"
        let shared = directory.appendingPathComponent("Shared.swift").path
        let own = (0..<2).map { directory.appendingPathComponent("Own\($0).swift").path }
        for path in own + [shared] {
            try source.write(toFile: path, atomically: true, encoding: .utf8)
        }

        for _ in 0..<3 {
            let windows = own.map { makeViewModel(selecting: [$0, shared]) }
            for window in windows {
                window.diagramMode = .dependencyGraph
                window.depsMode = .modules
                window.generate()
            }
            for window in windows {
                await window.currentTask?.value
            }
            for (window, file) in zip(windows, own) {
                let files = window.sourceReadNotices.compactMap { SourceReadNoticeBanner.Place(notice: $0)?.file }
                #expect(files.map(Self.resolved).sorted() == [file, shared].map(Self.resolved).sorted())
            }
        }
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @Test("the preview shows the banner when there are notices, and not while generating")
    func preview() async throws {
        let viewModel = makeViewModel(selecting: ["/p"])
        viewModel.sourceReadNotices = [notice("/p/Deep.swift")]
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            _ = try view.find(viewWithAccessibilityIdentifier: "sourceReadNoticeBanner")
        }
        viewModel.isGenerating = true
        try await DiagramPreviewView(viewModel: viewModel).inspectHosted { view in
            #expect(throws: InspectionError.self) {
                try view.find(viewWithAccessibilityIdentifier: "sourceReadNoticeBanner")
            }
        }
    }
}
