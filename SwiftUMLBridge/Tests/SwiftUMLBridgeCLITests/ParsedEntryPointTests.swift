@testable import swiftumlbridge
import Testing

// MARK: - Entry-point parsing

/// `Type.method` is the contract for `--entry` on the sequence and activity
/// commands. Everything the user can type reaches this function, so its
/// rejection behaviour is the CLI's whole input validation for that option.
@Suite("String.parsedEntryPoint")
struct ParsedEntryPointTests {

    @Test("a well-formed entry point splits into type and method")
    func splitsWellFormed() throws {
        let (type, method) = try "Loader.load".parsedEntryPoint()

        #expect(type == "Loader")
        #expect(method == "load")
    }

    @Test("a bare type name is rejected")
    func rejectsBareType() {
        #expect(throws: CLIError.self) { try "Loader".parsedEntryPoint() }
    }

    /// A nested or module-qualified name has three components and is rejected.
    /// Worth pinning: `MyModule.Loader.load` is a plausible thing to type, and
    /// the CLI refuses it rather than guessing which dot separates the method.
    @Test("a three-part name is rejected rather than guessed at")
    func rejectsThreeParts() {
        #expect(throws: CLIError.self) { try "MyModule.Loader.load".parsedEntryPoint() }
    }

    @Test("an empty string is rejected")
    func rejectsEmpty() {
        #expect(throws: CLIError.self) { try "".parsedEntryPoint() }
    }

    /// `split(separator:)` drops empty subsequences, so a leading or trailing
    /// dot yields one component and is rejected. Pinned because the behaviour
    /// depends on that `split` detail rather than on an explicit check — a
    /// future rewrite using `components(separatedBy:)` would return two
    /// components, one of them empty, and silently start accepting these.
    @Test("a dangling dot is rejected", arguments: ["Loader.", ".load", ".", ".."])
    func rejectsDanglingDot(input: String) {
        #expect(throws: CLIError.self) { try input.parsedEntryPoint() }
    }

    @Test("the thrown error is specifically invalidEntry")
    func throwsInvalidEntry() {
        do {
            _ = try "nope".parsedEntryPoint()
            Issue.record("expected a throw")
        } catch let error as CLIError {
            #expect(error.description == CLIError.invalidEntry.description)
        } catch {
            Issue.record("expected CLIError, got \(error)")
        }
    }
}
