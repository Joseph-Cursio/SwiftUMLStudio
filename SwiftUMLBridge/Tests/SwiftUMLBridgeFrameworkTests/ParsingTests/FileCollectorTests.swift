import Foundation
@testable import SwiftUMLBridgeFramework
import Testing

@Suite("FileCollector")
struct FileCollectorTests {

    private let collector = FileCollector()

    private let testDataURL: URL

    private var projectMockURL: URL {
        testDataURL.appendingPathComponent("ProjectMock")
    }

    init() throws {
        testDataURL = try #require(Bundle.module.resourceURL).appendingPathComponent("TestData")
    }

    // MARK: - getFiles(for url: URL) - single URL

    @Test("getFiles(for:) on a directory returns .swift files recursively")
    func getFilesForDirectory() {
        let files = collector.getFiles(for: projectMockURL)
        #expect(files.isEmpty == false)
        #expect(files.allSatisfy { $0.pathExtension == "swift" })
    }

    @Test("getFiles(for:) on a single .swift file returns that file")
    func getFilesForSingleFile() {
        let swiftFile = projectMockURL.appendingPathComponent("Level0.swift")
        let files = collector.getFiles(for: swiftFile)
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Level0.swift")
    }

    @Test("getFiles(for:) returns a non-existent directory's URL as given")
    func getFilesForNonExistentDirectory() {
        let url = URL(fileURLWithPath: "/nonexistent/path/dir")
        let files = collector.getFiles(for: url)
        // Only a directory is enumerated; any other URL, existing or not, is returned as-is.
        #expect(files == [url])
    }

    // MARK: - getFiles(for paths: [String], in directory: String)

    @Test("getFiles(for:in:) with empty paths uses directory itself")
    func getFilesEmptyPaths() {
        let files = collector.getFiles(for: [], in: projectMockURL.path)
        #expect(files.isEmpty == false)
    }

    @Test("getFiles(for:in:) with '.' uses directory")
    func getFilesWithDotPath() {
        let files = collector.getFiles(for: ["."], in: projectMockURL.path)
        #expect(files.isEmpty == false)
    }

    @Test("getFiles(for:in:) with absolute path returns files at that path")
    func getFilesWithAbsolutePath() {
        let swiftFile = projectMockURL.appendingPathComponent("Level0.swift")
        let files = collector.getFiles(for: [swiftFile.path], in: projectMockURL.path)
        #expect(files.count == 1)
    }

    @Test("getFiles(for:in:) with relative path appends to directory")
    func getFilesWithRelativePath() {
        let files = collector.getFiles(for: ["Level0.swift"], in: projectMockURL.path)
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "Level0.swift")
    }

    // MARK: - getFiles(for paths:, in directory:, honoring fileOptions:)

    @Test("getFiles with nil fileOptions returns all swift files")
    func getFilesNilOptions() {
        let files = collector.getFiles(
            for: [projectMockURL.path],
            in: projectMockURL.path,
            honoring: nil
        )
        #expect(files.isEmpty == false)
    }

    @Test("getFiles with empty include and exclude returns all files")
    func getFilesEmptyOptions() {
        let opts = FileOptions(include: [], exclude: [])
        let files = collector.getFiles(
            for: ["."],
            in: projectMockURL.path,
            honoring: opts
        )
        #expect(files.isEmpty == false)
    }

    @Test("getFiles with include pattern filters to matching files only")
    func getFilesWithIncludePattern() {
        var opts = FileOptions()
        opts.include = ["**/Mock*.swift"]
        let files = collector.getFiles(
            for: ["."],
            in: projectMockURL.path,
            honoring: opts
        )
        #expect(files.isEmpty == false)
        #expect(files.allSatisfy { $0.lastPathComponent.hasPrefix("Mock") })
    }

    @Test("getFiles with exclude pattern omits matching files")
    func getFilesWithExcludePattern() {
        var opts = FileOptions()
        opts.exclude = ["**/Mock*.swift"]
        let allFiles = collector.getFiles(for: ["."], in: projectMockURL.path, honoring: nil)
        let filteredFiles = collector.getFiles(
            for: ["."],
            in: projectMockURL.path,
            honoring: opts
        )
        #expect(filteredFiles.count < allFiles.count)
        #expect(filteredFiles.allSatisfy { !$0.lastPathComponent.hasPrefix("Mock") })
    }

    @Test("getFiles honors include entries written with . and .. components")
    func getFilesWithDotComponents() {
        func included(_ entry: String) -> Set<String> {
            var opts = FileOptions()
            opts.include = [entry]
            let files = collector.getFiles(for: ["."], in: projectMockURL.path, honoring: opts)
            return Set(files.map(\.lastPathComponent))
        }
        let mocks = included("**/Mock*.swift")
        #expect(mocks.isEmpty == false)
        #expect(included("./**/Mock*.swift") == mocks)
        #expect(included("Level 1/../**/Mock*.swift") == mocks)
        #expect(included("./Mock0File.swift") == ["Mock0File.swift"])
    }

    @Test("getFiles excludes hidden files")
    func getFilesExcludesHiddenFiles() {
        let files = collector.getFiles(for: projectMockURL)
        #expect(files.allSatisfy { !$0.lastPathComponent.hasPrefix(".") })
    }
}
