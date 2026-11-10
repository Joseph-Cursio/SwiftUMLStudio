@testable import SwiftUMLBridgeFramework
import Testing

@Suite("BrowserPresenter")
struct BrowserPresenterTests {

    @Test("default format is .default")
    func defaultFormatIsDefault() {
        let presenter = BrowserPresenter()
        switch presenter.format {
        case .default:
            #expect(Bool(true))
        default:
            Issue.record("Expected .default format")
        }
    }

    @Test("png format is preserved")
    func pngFormatPreserved() {
        let presenter = BrowserPresenter(format: .png)
        switch presenter.format {
        case .png:
            #expect(Bool(true))
        default:
            Issue.record("Expected .png format")
        }
    }

    @Test("svg format is preserved")
    func svgFormatPreserved() {
        let presenter = BrowserPresenter(format: .svg)
        switch presenter.format {
        case .svg:
            #expect(Bool(true))
        default:
            Issue.record("Expected .svg format")
        }
    }

    @Test("BrowserPresenter conforms to DiagramPresenting")
    func conformsToDiagramPresenting() {
        let presenter: DiagramPresenting = BrowserPresenter()
        #expect(presenter is BrowserPresenter)
    }
}
