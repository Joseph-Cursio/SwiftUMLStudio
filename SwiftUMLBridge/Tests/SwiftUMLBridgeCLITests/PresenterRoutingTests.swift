@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// MARK: - Output routing

@Suite("ClassDiagramOutput presenter routing")
struct PresenterRoutingTests {

    @Test("consoleOnly routes to the console presenter")
    func consoleRouting() {
        let output: ClassDiagramOutput? = .consoleOnly
        #expect(output.presenter is ConsolePresenter)
    }

    @Test("browserImageOnly routes to the browser presenter")
    func browserImageRouting() {
        let output: ClassDiagramOutput? = .browserImageOnly
        #expect(output.presenter is BrowserPresenter)
    }

    @Test("browser routes to the browser presenter")
    func browserRouting() {
        let output: ClassDiagramOutput? = .browser
        #expect(output.presenter is BrowserPresenter)
    }

    /// Omitting `--output` must open the browser, matching the documented
    /// default. This is the branch a user hits by typing nothing at all.
    @Test("no --output defaults to the browser presenter")
    func defaultRouting() {
        let output: ClassDiagramOutput? = nil
        #expect(output.presenter is BrowserPresenter)
    }
}
