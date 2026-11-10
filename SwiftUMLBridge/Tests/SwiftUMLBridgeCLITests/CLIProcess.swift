import Foundation
import Testing

/// Runs the built `swiftumlbridge` executable with `directory` as its working
/// directory, returning the exit status and stdout and stderr combined.
func runCLI(_ arguments: [String], in directory: URL) throws -> (status: Int32, output: String) {
    // `swift test` builds the executable product into the directory that also
    // holds this test bundle.
    let executable = Bundle(for: TestBundleMarker.self).bundleURL
        .deletingLastPathComponent()
        .appendingPathComponent("swiftumlbridge")
    try #require(
        FileManager.default.isExecutableFile(atPath: executable.path),
        "no swiftumlbridge executable beside the test bundle at \(executable.path)"
    )

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    // One pipe for both streams: draining two in turn can deadlock once the
    // one not being read fills its buffer.
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return (process.terminationStatus, try #require(String(bytes: output, encoding: .utf8)))
}
