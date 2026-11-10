/// Print script to console
public struct ConsolePresenter: DiagramPresenting {
    public init() {
        // Public because a struct's implicit initializer is internal; there is no state to set.
    }

    public func present(script: any DiagramOutputting) {
        print(script.text)
    }
}
