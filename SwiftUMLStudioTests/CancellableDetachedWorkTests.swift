import Foundation
import SwiftUMLBridgeFramework
@testable import SwiftUMLStudio
import Testing

/// A detached task takes on no cancellation from the task awaiting it, so `cancellableDetached`
/// passes it on: a generation `generate()` replaced then stops parsing rather than running to
/// its end (#236).
@Suite("Detached work takes on the cancel of the task awaiting it")
struct CancellableDetachedWorkTests {

    /// The work waits, up to ten seconds, for its own task to be cancelled.
    @Test("cancelling the awaiting task cancels the work")
    func cancelReachesWork() async {
        let awaiting = Task {
            await cancellableDetached { () -> Bool in
                let deadline = Date().addingTimeInterval(10)
                while !Task.isCancelled, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return Task.isCancelled
            }
        }
        awaiting.cancel()
        #expect(await awaiting.value)
    }

    @Test("work no one cancels runs to its result")
    func uncancelledWorkRuns() async {
        let result = await cancellableDetached { (1...10).reduce(0, +) }
        #expect(result == 55)
    }

    // MARK: - Source read notices

    /// A file whose `[` nest past the Bridge's limit, so parsing it records a notice. The caller
    /// removes the directory.
    private static func deepFile() throws -> (directory: URL, path: String) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("detached-notices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let chain = String(repeating: "[", count: 30) + "1" + String(repeating: "]", count: 30)
        let path = directory.appendingPathComponent("Deep.swift").path
        try "let x = \(chain)\n".write(toFile: path, atomically: true, encoding: .utf8)
        return (directory, path)
    }

    /// The detached task takes no task-locals, so `cancellableDetached` binds the caller's
    /// collector inside it.
    @Test("work records its notices into the awaiting task's collector")
    func noticesReachCallersCollector() async throws {
        let file = try Self.deepFile()
        defer { try? FileManager.default.removeItem(at: file.directory) }
        let collector = SourceReadNoticeCollector()
        await SourceReadNotices.$collector.withValue(collector) {
            _ = await cancellableDetached {
                ClassDiagramGenerator().generateScript(for: [file.path], with: .default)
            }
        }
        #expect(collector.notices.contains { $0.hasPrefix(file.path + ":") })
    }

    /// With no collector to pass on, the work gets one of its own, as Studio reads nothing from
    /// the framework's process-wide list: the project analysis runs this way. Other suites may
    /// record into that list at the same time, so only this file's notice is looked for.
    @Test("work whose caller has no collector records nothing into the process-wide list")
    func noticesStayOutOfProcessList() async throws {
        let file = try Self.deepFile()
        defer { try? FileManager.default.removeItem(at: file.directory) }
        _ = await cancellableDetached {
            ClassDiagramGenerator().generateScript(for: [file.path], with: .default)
        }
        #expect(!SourceReadNotices.drain().contains { $0.hasPrefix(file.path + ":") })
    }
}
