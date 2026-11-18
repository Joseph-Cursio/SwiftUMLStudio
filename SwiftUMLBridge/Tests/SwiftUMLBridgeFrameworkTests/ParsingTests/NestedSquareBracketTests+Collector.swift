import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

/// A run that binds `SourceReadNotices.collector` gets its own parses' notices, and the
/// process-wide list gets none, so two runs at once (two Studio windows) cannot take each other's.
/// In the serialized suite, as they check the process-wide list.
extension NestedSquareBracketTests {
    private static let deepSource = file("let x = " + chain("[", "1", "]", depth: 24))

    /// The generator parses on a `ParsingStack` thread, which must take the collector with it.
    @Test("a bound collector gets the run's notice, and the process-wide list does not")
    func collectorGetsTheNotice() throws {
        _ = SourceReadNotices.drain()
        let collector = SourceReadNoticeCollector()
        try withSourceFile(Self.deepSource) { url in
            SourceReadNotices.$collector.withValue(collector) {
                _ = ClassDiagramGenerator().generateScript(for: [url.path], with: Configuration(format: .plantuml))
                _ = StateMachineGenerator().findCandidates(for: [url.path])
            }
            #expect(collector.notices.count == 1)
            #expect(collector.notices.first?.hasPrefix("\(url.path):2:") == true)
        }
        #expect(SourceReadNotices.drain().isEmpty)
    }

    /// Each run records into its own collector, so neither takes the other's notice, and a file
    /// both read gives each run its notice: the process-wide list kept one copy for both.
    @Test("two runs at once each get their own notices, and one each for a file both read")
    func concurrentRuns() async throws {
        _ = SourceReadNotices.drain()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nested-brackets-runs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = directory.appendingPathComponent("Shared.swift").path
        let own = (0..<2).map { directory.appendingPathComponent("Own\($0).swift").path }
        for path in own + [shared] {
            try Self.deepSource.write(toFile: path, atomically: true, encoding: .utf8)
        }

        let collected = await withTaskGroup(of: (Int, [String]).self) { group in
            for run in 0..<2 {
                group.addTask {
                    let collector = SourceReadNoticeCollector()
                    SourceReadNotices.$collector.withValue(collector) {
                        _ = ClassDiagramGenerator().generateScript(
                            for: [own[run], shared], with: Configuration(format: .plantuml)
                        )
                    }
                    return (run, collector.notices)
                }
            }
            var byRun: [Int: [String]] = [:]
            for await (run, notices) in group { byRun[run] = notices }
            return byRun
        }

        for run in 0..<2 {
            let files = (collected[run] ?? []).map { String($0.prefix { $0 != ":" }) }.sorted()
            #expect(files == [own[run], shared].sorted(), "run \(run)")
        }
        #expect(SourceReadNotices.drain().isEmpty)
    }
}
