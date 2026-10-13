import Foundation
import SwiftUI
import Testing
import ViewInspector
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio

/// The PlantUML preview contacts planttext.com only with consent.
///
/// No test here inspects a granted preview's body: that would build a real `WebView(url:)`.
/// The pure ``PlantTextPreview/content(for:isGranted:)`` covers that case instead.
@Suite("PlantTextPreview")
@MainActor
struct PlantTextPreviewTests {

    private let plantUML = SimpleDiagramScript(text: "@startuml\nclass Foo\n@enduml", format: .plantuml)

    @Test("a PlantUML script waits for consent")
    func waitsForConsent() {
        #expect(PlantTextPreview.content(for: plantUML, isGranted: false) == .consentCard)
    }

    @Test("with consent it loads planttext.com's rendering of the script")
    func rendersWithConsent() throws {
        let url = try #require(URL(string: "https://www.planttext.com/api/plantuml/svg/" + plantUML.encodeText()))
        #expect(PlantTextPreview.content(for: plantUML, isGranted: true) == .render(url))
    }

    @Test("empty text neither asks nor loads", arguments: [false, true])
    func emptyTextShowsNothing(isGranted: Bool) {
        // The Bridge's "no entities found" script is typed PlantUML whatever format was requested.
        #expect(ERScript.empty.format == .plantuml)
        #expect(PlantTextPreview.content(for: ERScript.empty, isGranted: isGranted) == .nothing)
    }

    @Test("only PlantUML goes to planttext.com", arguments: [DiagramFormat.mermaid, .nomnoml, .svg])
    func otherFormatsNeverLoad(format: DiagramFormat) {
        let script = SimpleDiagramScript(text: "graph TD\nA --> B", format: format)
        #expect(PlantTextPreview.content(for: script, isGranted: true) == .nothing)
    }

    @Test("the card's Allow button grants consent")
    func allowGrantsConsent() throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let view = PlantTextPreview(script: plantUML, requestedFormat: .plantuml, consent: consent)

        let card = try view.inspect().find(PlantUMLConsentCard.self).actualView()
        #expect(card.isFallback == false)
        #expect(card.onUseMermaid == nil)
        card.onAllow()

        #expect(consent.decision == .granted)
    }

    @Test("Use Mermaid Instead records the decline, then switches format")
    func useMermaidDeclinesAndSwitches() throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        var switched = false
        let view = PlantTextPreview(
            script: plantUML, requestedFormat: .plantuml, consent: consent, onUseMermaid: { switched = true }
        )

        let card = try view.inspect().find(PlantUMLConsentCard.self).actualView()
        let useMermaid = try #require(card.onUseMermaid)
        useMermaid()

        #expect(consent.decision == .declined)
        #expect(switched)
    }

    @Test("a declined preview still asks rather than loading")
    func declinedStillAsks() throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent(.declined)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let view = PlantTextPreview(script: plantUML, requestedFormat: .plantuml, consent: consent)
        _ = try view.inspect().find(PlantUMLConsentCard.self)
    }

    @Test("the card explains a PlantUML script when another format was picked")
    func fallbackIsExplained() throws {
        let (consent, suiteName) = PlantUMLConsentTestSupport.makeConsent()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let view = PlantTextPreview(script: plantUML, requestedFormat: .nomnoml, consent: consent)
        #expect(try view.inspect().find(PlantUMLConsentCard.self).actualView().isFallback)
    }
}

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
