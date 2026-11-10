import Foundation

/// Print script to console
public struct ConsolePresenter: DiagramPresenting {
    public init() {}

    public func present(script: any DiagramOutputting) {
        print(script.text)
    }
}
