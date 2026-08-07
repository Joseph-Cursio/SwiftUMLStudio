import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// Regression cover for the subprocess plumbing in
/// `SPMPackageReader.describe(at:)`, which shells out to
/// `swift package describe --type json`.
///
/// The bug being pinned: draining the child's output *after* `waitUntilExit()`
/// deadlocks once that output outgrows the pipe buffer (~64KB on Darwin). The
/// child blocks writing into a full pipe nobody is reading; the parent blocks
/// waiting for a child that cannot proceed. Neither ever moves.
///
/// Verified against the pre-fix code: `survivesLargeOutput` hung for over ten
/// minutes on a package whose describe output is ~120KB, where the fixed
/// version returns in about a second.
///
/// The time limits below only bite because `describe(at:)` runs a watchdog.
/// `.timeLimit` cancels the *task*, and cancellation is cooperative — it cannot
/// interrupt a thread already blocked in `readDataToEndOfFile()`. Both halves
/// were measured:
///
/// - With no watchdog (the original pipe bug), the two-minute limit never fired
///   and the run had to be killed by hand.
/// - With the watchdog but no `--scratch-path`, the lock test reported the
///   limit and ended after ~320s — the watchdog killed the subprocess, closing
///   the pipes, which let the blocked thread unwind so the limit could surface.
///
/// So the limits are a backstop on top of the watchdog, not a substitute for
/// it. A regression that removes the watchdog goes back to hanging outright.
@Suite("SPMPackageDescription.describe subprocess")
struct SPMPackageDescribeProcessTests {

    /// Writes a package whose `describe` output is far larger than the pipe
    /// buffer. Size comes from the `sources` array: every file is listed by
    /// path, so many long-named files inflate the JSON cheaply — no compilation
    /// happens, SwiftPM only enumerates.
    private func makeWidePackage(sourceCount: Int) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-describe-wide-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/Wide")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

        let manifest = """
            // swift-tools-version: 5.9
            import PackageDescription

            let package = Package(name: "Wide", targets: [.target(name: "Wide")])
            """
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        // Long names so each `sources` entry costs ~60 bytes of JSON.
        for index in 0..<sourceCount {
            let name = "GeneratedSourceFileWithADeliberatelyLongName\(index).swift"
            try "struct Generated\(index) {}"
                .write(
                    to: sources.appendingPathComponent(name),
                    atomically: true, encoding: .utf8
                )
        }
        return root
    }

    @Test(
        "describe survives output larger than the pipe buffer",
        .timeLimit(.minutes(2))
    )
    func survivesLargeOutput() throws {
        let root = try makeWidePackage(sourceCount: 2_000)
        defer { try? FileManager.default.removeItem(at: root) }

        let description = try SPMPackageReader.describe(at: root)

        #expect(description.name == "Wide")
        #expect(description.targets.count == 1)
        #expect(
            description.targets.first?.sources.count == 2_000,
            "every source must survive the read, not just the first bufferful"
        )
    }

    @Test("describe reads a small package correctly", .timeLimit(.minutes(1)))
    func readsSmallPackage() throws {
        let root = try makeWidePackage(sourceCount: 3)
        defer { try? FileManager.default.removeItem(at: root) }

        let description = try SPMPackageReader.describe(at: root)

        #expect(description.name == "Wide")
        #expect(description.targets.first?.sources.count == 3)
    }

    /// The lock-contention regression, and the reason `describe(at:)` passes
    /// `--scratch-path`.
    ///
    /// SwiftPM locks its scratch directory for the length of a command. This
    /// test describes the very package the suite is running from, so the
    /// package's own `.build` is locked by the `swift test` that invoked us.
    /// Without a private scratch path the child waits on that lock forever and
    /// the CLI hangs with no output — the failure that first showed up as the
    /// component integration tests never finishing.
    ///
    /// If this test ever hangs rather than fails, `--scratch-path` has been
    /// dropped from the argument list.
    @Test("describing the package under test does not block on its build lock",
          .timeLimit(.minutes(2)))
    func describesPackageWhoseBuildDirectoryIsLocked() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ModelTests
            .deletingLastPathComponent()  // SwiftUMLBridgeFrameworkTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SwiftUMLBridge — the package root

        let description = try SPMPackageReader.describe(at: packageRoot)

        #expect(description.name == "SwiftUMLBridge")
        #expect(
            description.targets.contains { $0.name == "SwiftUMLBridgeFramework" },
            "expected the framework target in the description"
        )
    }

    /// The failure path also reads a pipe. A directory with no manifest makes
    /// the tool exit non-zero and write to stderr, so this covers the branch
    /// that surfaces `stderr` in the thrown error.
    @Test("a directory with no manifest throws rather than hanging", .timeLimit(.minutes(1)))
    func throwsWithoutManifest() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spm-describe-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            _ = try SPMPackageReader.describe(at: root)
        }
    }
}
