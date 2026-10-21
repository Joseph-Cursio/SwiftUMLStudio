import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// With an SDK path, the SourceKit typename supplement gives a stored property with no written
/// type the type Swift infers for it. Without one, it knows only the written types. Until #147,
/// `--sdk` reached SourceKit with no file path, so no cursor info was sent and nothing was
/// inferred.
///
/// The suite runs in parallel on purpose: SourceKit cancels a cursor-info request when another
/// arrives unless each request says not to, and only concurrent parses show the lost types.
@Suite("The typename supplement resolves inferred types when given an SDK")
struct InferredTypenameTests {
    /// `xcrun --show-sdk-path -sdk macosx`, or nil on a machine without an SDK.
    static let sdkPath: String? = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path", "-sdk", "macosx"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return process.terminationStatus == 0 && !path.isEmpty ? path : nil
    }()

    /// Writes `files` to a fresh directory, returns it, and the caller removes it.
    private func directory(with files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inferred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    /// The PlantUML class diagram's member lines for `files`, written to a fresh directory.
    private func members(_ files: [String: String], sdkPath: String?) throws -> [String] {
        let directory = try directory(with: files.mapValues { Data($0.utf8) })
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = ClassDiagramGenerator()
            .generateScript(for: [directory.path], with: Configuration(format: .plantuml), sdkPath: sdkPath)
            .text
        return Self.memberLines(text)
    }

    private static func memberLines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("~") }
    }

    @Test("literals and initialisers give their inferred type", .enabled(if: sdkPath != nil))
    func inferredFromLiterals() throws {
        let members = try members([
            "S.swift": "struct S { var count = 0; var name = \"a\"; var flag = true; var typed: Double = 1 }"
        ], sdkPath: Self.sdkPath)
        #expect(members == ["~count : Int", "~name : String", "~flag : Bool", "~typed : Double"])
    }

    @Test("a static property in an extension and a nested type's property", .enabled(if: sdkPath != nil))
    func extensionAndNesting() throws {
        let members = try members([
            "Store.swift": """
                final class Store {
                    var items = [String]()
                    struct Inner { var depth = 0.5 }
                }
                extension Store {
                    static let shared = Store()
                }
                """
        ], sdkPath: Self.sdkPath)
        #expect(members.contains("~items : [String]"), "\(members)")
        #expect(members.contains("~depth : Double"), "\(members)")
        #expect(members.contains("~{static} shared : Store"), "\(members)")
    }

    @Test("a type the file cannot see is left unwritten, not shown as `_`", .enabled(if: sdkPath != nil))
    func unresolvedIsLeftOut() throws {
        let members = try members([
            "Store.swift": "struct Store { var cache = Cache() }",
            "Cache.swift": "struct Cache { var hits = 0 }"
        ], sdkPath: Self.sdkPath)
        #expect(members.contains("~cache"), "\(members)")
        #expect(members.contains("~hits : Int"), "\(members)")
    }

    /// Reading a file into a `String` drops its byte-order mark, so the offsets the parsers give
    /// are 3 short of the file's, which cursor info reads.
    @Test("a file that starts with a byte-order mark", .enabled(if: sdkPath != nil))
    func byteOrderMark() throws {
        let directory = try directory(with: [
            "S.swift": Data([0xEF, 0xBB, 0xBF]) + Data("struct S {\n    var count = 0\n    var name = \"a\"\n}\n".utf8)
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = ClassDiagramGenerator()
            .generateScript(for: [directory.path], with: Configuration(format: .plantuml), sdkPath: Self.sdkPath)
            .text
        #expect(Self.memberLines(text) == ["~count : Int", "~name : String"])
    }

    @Test("a package's files resolve inferred types too", .enabled(if: sdkPath != nil))
    func packageMode() throws {
        let root = try directory(with: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources/Core", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("struct S { var count = 0 }".utf8).write(to: sources.appendingPathComponent("S.swift"))
        let description = SPMPackageDescription(name: "Demo", targets: [
            SPMTargetDescription(
                name: "Core", kind: .library, path: "Sources/Core", sources: ["S.swift"], dependencies: []
            )
        ])
        let text = ClassDiagramGenerator().generateScript(
            forPackage: description, packageRoot: root, with: Configuration(format: .plantuml), sdkPath: Self.sdkPath
        ).text
        #expect(Self.memberLines(text) == ["~count : Int"], "\(text)")
    }

    @Test("without an SDK only written types are known")
    func noSDKKeepsWrittenTypesOnly() throws {
        let members = try members([
            "S.swift": "struct S { var count = 0; var typed: Double = 1 }"
        ], sdkPath: nil)
        #expect(members == ["~count", "~typed : Double"])
    }
}
