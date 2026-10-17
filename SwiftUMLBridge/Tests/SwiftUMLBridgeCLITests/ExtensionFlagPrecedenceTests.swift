import Foundation
import Testing

/// One `classdiagram` run: the `elements.showExtensions` its `.swiftumlbridge.yml` sets, if it
/// has one, the extension flags passed, and what the PlantUML must and must not hold.
struct FlagCase: CustomTestStringConvertible, Sendable {
    let showExtensions: String?
    let flags: [String]
    let present: [String]
    let absent: [String]

    var testDescription: String {
        "config \(showExtensions ?? "none"), flags \(flags.isEmpty ? "none" : flags.joined(separator: " "))"
    }
}

/// `--show-extensions`, `--merge-extensions` and `--hide-extensions` override the config file's
/// `elements.showExtensions`, as `--format` overrides `format`, and the last of several wins, as
/// `docs/user/reference.md` says. They used to apply only when the file left the key out, and
/// two of them were a usage error (#156).
@Suite("CLI integration — classdiagram extension flags")
struct ExtensionFlagPrecedenceTests {

    private static let extensionBox = "<< (X, orchid) extension >>"
    private static let mergedMember = "~bar <&bolt>"

    static let cases = [
        FlagCase(showExtensions: "merged", flags: ["--show-extensions"],
                 present: [extensionBox], absent: [mergedMember]),
        FlagCase(showExtensions: "merged", flags: ["--hide-extensions"], present: ["as Foo "], absent: ["bar"]),
        FlagCase(showExtensions: "all", flags: ["--merge-extensions"],
                 present: [mergedMember], absent: [extensionBox]),
        FlagCase(showExtensions: nil, flags: ["--merge-extensions", "--show-extensions"],
                 present: [extensionBox], absent: [mergedMember]),
        FlagCase(showExtensions: nil, flags: ["--show-extensions", "--merge-extensions"],
                 present: [mergedMember], absent: [extensionBox]),
        FlagCase(showExtensions: nil, flags: ["--hide-extensions", "--show-extensions"],
                 present: [extensionBox], absent: [mergedMember]),
        // With no flag, the config file decides, and without one, extensions get boxes.
        FlagCase(showExtensions: "merged", flags: [], present: [mergedMember], absent: [extensionBox]),
        FlagCase(showExtensions: nil, flags: [], present: [extensionBox], absent: [mergedMember])
    ]

    @Test("the flag decides", arguments: cases)
    func flagDecides(_ flagCase: FlagCase) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-cli-flags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Foo {}\nextension Foo { func bar() {} }\n"
            .write(to: root.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        if let showExtensions = flagCase.showExtensions {
            try "elements:\n  showExtensions: \(showExtensions)\n"
                .write(to: root.appendingPathComponent(".swiftumlbridge.yml"), atomically: true, encoding: .utf8)
        }

        let run = try runCLI(
            ["classdiagram", "Model.swift", "--format", "plantuml", "--output", "consoleOnly"] + flagCase.flags,
            in: root
        )

        #expect(run.status == 0, "\(run.output)")
        for text in flagCase.present {
            #expect(run.output.contains(text), "missing \(text) in \(run.output)")
        }
        for text in flagCase.absent {
            #expect(!run.output.contains(text), "unexpected \(text) in \(run.output)")
        }
    }
}
