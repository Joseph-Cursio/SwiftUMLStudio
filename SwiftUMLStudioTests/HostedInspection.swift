import Foundation
import SwiftUI
import ViewInspector
@testable import SwiftUMLStudio

extension Inspection: @retroactive InspectionEmissary { }

/// A view that keeps an `Inspection`, so a test can read it while SwiftUI
/// hosts it. Reading an un-hosted view's `@State` makes SwiftUI warn that the
/// state is not installed, and gives back only the initial value.
@MainActor
protocol HostedInspectable: View {
    var inspection: Inspection<Self> { get }
}

extension HostedInspectable {
    /// Hosts the view, runs `body` once its `@State` is installed, and
    /// returns what `body` returned.
    @discardableResult
    func inspectHosted<T>(
        _ body: @escaping @MainActor @Sendable (InspectableView<ViewType.View<Self>>) throws -> T
    ) async throws -> T {
        // Tests run in parallel, and ViewHosting tells hosted views apart by this key.
        let key = UUID().uuidString
        let result = HostedResult<T>()
        try await ViewHosting.host(self, function: key) {
            try await inspection.inspect(function: key) { view in
                result.value = try body(view)
            }
        }
        guard let value = result.value else {
            throw InspectionError.notSupported("The hosted view was never inspected")
        }
        return value
    }
}

@MainActor
private final class HostedResult<T> {
    var value: T?
}

extension DiagramExportMenu: HostedInspectable { }
extension DiagramPreviewView: HostedInspectable { }
extension DiagramWebView: HostedInspectable { }
extension ExplorerSidebar: HostedInspectable { }
extension WorkspaceSidebar: HostedInspectable { }
