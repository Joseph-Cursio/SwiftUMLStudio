import Foundation
@testable import swiftumlbridge
import SwiftUMLBridgeFramework
import Testing

// Argument parsing only — no command is `run()`, so nothing here parses Swift
// source or writes output. What is under test is the contract between what a
// user types and what the command ends up holding: defaults, required options,
// and the flag precedence the commands document in comments but never asserted.

// MARK: - er

@Suite("er command parsing")
struct ERCommandParsingTests {

    @Test("paths are optional and collected when given")
    func paths() throws {
        #expect(try CLI.ERCommand.parse([]).paths.isEmpty)
        #expect(try CLI.ERCommand.parse(["Models", "Store.xcdatamodeld"]).paths
            == ["Models", "Store.xcdatamodeld"])
    }
}
