import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// `SPMPackageReader.ReadError` says what went wrong in words, not as the case Swift would dump (#282).
@Suite("SPMPackageReader.ReadError descriptions")
struct SPMPackageReaderErrorTests {

    @Test("a failed swift package run gives its exit status and what it said, trimmed")
    func swiftToolFailed() {
        let error = SPMPackageReader.ReadError.swiftToolFailed(exitStatus: 1, stderr: "error: boom\n")

        #expect(error.localizedDescription == "`swift package` exited with status 1: error: boom")
    }

    @Test("a failed run that said nothing gives only its exit status")
    func swiftToolFailedSilently() {
        let error = SPMPackageReader.ReadError.swiftToolFailed(exitStatus: 2, stderr: " \n")

        #expect(error.localizedDescription == "`swift package` exited with status 2")
    }

    @Test("unreadable output names the reason")
    func malformedJSON() {
        let error = SPMPackageReader.ReadError.malformedJSON("missing 'name'")

        #expect(
            error.localizedDescription == "could not read the output of `swift package describe` (missing 'name')"
        )
    }

    @Test("a timeout gives the limit in seconds", arguments: [
        (300.0, "300"), (0.5, "0.5"),
    ])
    func timedOut(seconds: TimeInterval, written: String) {
        let error = SPMPackageReader.ReadError.timedOut(seconds: seconds)

        #expect(error.localizedDescription == "`swift package` was stopped after \(written) seconds without finishing")
    }
}
