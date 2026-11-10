@testable import SwiftUMLBridgeFramework
import Testing

@Suite("ConsolePresenter")
struct ConsolePresenterTests {

    @Test("present() completes without error")
    func presentCompletes() {
        let presenter = ConsolePresenter()
        let script = DiagramScript(items: [], configuration: .default)
        presenter.present(script: script)
        #expect(Bool(true))
    }

    @Test("ConsolePresenter can be instantiated with default init")
    func defaultInit() {
        let _: any DiagramPresenting = ConsolePresenter()
        #expect(Bool(true))
    }

    @Test("present() does not throw")
    func presentDoesNotThrow() {
        let presenter = ConsolePresenter()
        let generator = ClassDiagramGenerator()
        let script = generator.generateScript(for: "struct Foo {}")
        presenter.present(script: script)
        #expect(Bool(true))
    }
}
