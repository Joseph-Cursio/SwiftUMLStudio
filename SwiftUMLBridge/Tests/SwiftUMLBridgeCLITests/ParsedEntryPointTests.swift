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

    /// A method of a nested type, as `extension NS.Real { func run() }`, is listed as `NS.Real.run`,
    /// so the last dot separates the method (#234). A module-qualified name reads the same way,
    /// as a type `MyModule.Loader`, and draws an empty diagram rather than an error.
    @Test(
        "a three-part name splits at the last dot",
        arguments: [
            ("NS.Real.run", "NS.Real", "run"),
            ("MyModule.Loader.load", "MyModule.Loader", "load"),
        ]
    )
    func splitsThreePartsAtLastDot(entry: String, expectedType: String, expectedMethod: String) throws {
        let (type, method) = try entry.parsedEntryPoint()
        #expect(type == expectedType)
        #expect(method == expectedMethod)
    }

    @Test("an empty string is rejected")
    func rejectsEmpty() {
        #expect(throws: CLIError.self) { try "".parsedEntryPoint() }
    }

    /// Any part left empty, by a leading, trailing or doubled dot, is rejected: `EntryPointName`
    /// checks every part, so `Loader..load` cannot read as a type `Loader.`.
    @Test("a dangling or doubled dot is rejected", arguments: ["Loader.", ".load", ".", "..", "Loader..load"])
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
