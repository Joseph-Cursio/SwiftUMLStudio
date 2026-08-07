import Testing
@testable import swiftumlbridge

/// Proves the executable target links into a test bundle at all. The CLI is
/// declared with `@main`, which can collide with the test runner's own entry
/// point; if that ever regresses, this fails first and unambiguously rather
/// than surfacing as a confusing link error in a behavioural test.
@Suite("CLI linkage")
struct LinkageSmokeTests {

    @Test("the root command exposes its configured name")
    func rootCommandName() {
        #expect(SwiftUMLBridgeCLI.configuration.commandName == "swiftumlbridge")
    }
}
