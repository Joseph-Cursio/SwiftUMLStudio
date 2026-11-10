import Foundation
import Testing

/// Keeps planttext.com behind ``PlantTextPreview``: a second call site would skip the consent check.
@Suite("planttext.com call site")
struct PlantTextCallSiteTests {

    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()                // SwiftUMLStudioTests/
            .deletingLastPathComponent()                // repository root
            .appendingPathComponent("SwiftUMLStudio")
    }

    @Test("only PlantTextPreview builds a planttext.com request or loads a remote web view")
    func onlyPlantTextPreviewContactsPlantText() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        try #require(files.contains { $0.lastPathComponent == "PlantTextPreview.swift" })

        let offenders = try files
            .filter { $0.lastPathComponent != "PlantTextPreview.swift" }
            .filter { file in
                let source = try String(contentsOf: file, encoding: .utf8)
                return source.contains("planttext.com/api")
                    || source.contains("WebView(url:")
                    || source.contains("BrowserPresenter")
            }
            .map(\.lastPathComponent)
        #expect(offenders.isEmpty)
    }
}
