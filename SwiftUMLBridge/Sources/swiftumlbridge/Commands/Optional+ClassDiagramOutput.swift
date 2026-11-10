import ArgumentParser
import Foundation
import SwiftUMLBridgeFramework

extension Optional where Wrapped == ClassDiagramOutput {
    /// The presenter selected by this output option (defaults to the browser).
    var presenter: any DiagramPresenting {
        switch self {
        case .browserImageOnly: return BrowserPresenter(format: .png)
        case .consoleOnly:      return ConsolePresenter()
        default:                return BrowserPresenter(format: .default)
        }
    }

    /// The routed presenter, wrapped to warn when the SVG layout fell back to its grid.
    var reportingPresenter: any DiagramPresenting {
        LayoutFallbackReporter(inner: presenter)
    }

    /// Present `script` using the presenter selected by this output option.
    func present(_ script: any DiagramOutputting) async {
        await reportingPresenter.present(script: script)
    }
}
