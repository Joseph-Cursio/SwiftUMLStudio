import Foundation
import Testing

/// One `deps` run: the `elements:` block its `.swiftumlbridge.yml` holds, if it has one, the
/// arguments passed, and what the PlantUML must and must not hold.
struct DepsFilterCase: CustomTestStringConvertible, Sendable {
    let label: String
    let elements: String?
    let arguments: [String]
    let present: [String]
    let absent: [String]

    var testDescription: String { label }
}

/// `--public-only` and `--exclude` each set only their own `elements` key, so the config file's
/// other keys still apply, and both excludes reach `--modules` runs, with paths and with
/// `--package` (#161). `--public-only` used to drop the file's `elements.exclude`, and no exclude
/// was read in modules mode.
@Suite("CLI integration — deps filter scope")
struct DepsFilterScopeTests {

    static let cases = [
        DepsFilterCase(
            label: "--public-only keeps elements.exclude",
            elements: "exclude: [Generated]", arguments: ["Types", "--public-only"],
            present: ["Square --> Shape : conforms"], absent: ["Generated", "Helper"]
        ),
        DepsFilterCase(
            label: "--modules applies --exclude",
            elements: nil, arguments: ["Mods", "--modules", "--exclude", "Foundation"],
            present: ["App --> Dispatch : imports"], absent: ["Foundation"]
        ),
        DepsFilterCase(
            label: "--modules applies elements.exclude",
            elements: "exclude: [Foundation]", arguments: ["Mods", "--modules"],
            present: ["App --> Dispatch : imports"], absent: ["Foundation"]
        ),
        DepsFilterCase(
            label: "--package --modules applies --exclude",
            elements: nil, arguments: ["--package", "Pkg", "--modules", "--exclude", "Core"],
            present: ["component \"App\" as App <<library>>"], absent: ["Core"]
        ),
        // The rest are guards: each passed before the fix too.
        DepsFilterCase(
            label: "--exclude keeps havingAccessLevel",
            elements: "havingAccessLevel: [public]", arguments: ["Types", "--exclude", "Square"],
            present: ["Generated --> Shape : conforms"], absent: ["Square", "Helper"]
        ),
        DepsFilterCase(
            label: "--exclude replaces elements.exclude",
            elements: "exclude: [Generated]", arguments: ["Types", "--exclude", "Square"],
            present: ["Generated --> Shape", "Helper --> Shape"], absent: ["Square"]
        ),
        DepsFilterCase(
            label: "--public-only --exclude",
            elements: nil, arguments: ["Types", "--public-only", "--exclude", "Square"],
            present: ["Generated --> Shape : conforms"], absent: ["Square", "Helper"]
        ),
        DepsFilterCase(
            label: "no filter",
            elements: nil, arguments: ["Types"],
            present: ["Square --> Shape", "Generated --> Shape", "Helper --> Shape"], absent: []
        ),
        DepsFilterCase(
            label: "--modules, no filter",
            elements: nil, arguments: ["Mods", "--modules"],
            present: ["App --> Foundation", "App --> Dispatch", "Core --> Foundation"], absent: []
        )
    ]

    @Test("each filter reaches the graph", arguments: cases)
    func filterApplies(_ filterCase: DepsFilterCase) throws {
        let root = try Self.makeProject()
        defer { try? FileManager.default.removeItem(at: root) }
        if let elements = filterCase.elements {
            try "elements:\n  \(elements)\n"
                .write(to: root.appendingPathComponent(".swiftumlbridge.yml"), atomically: true, encoding: .utf8)
        }

        let run = try runCLI(
            ["deps"] + filterCase.arguments + ["--format", "plantuml", "--output", "consoleOnly"], in: root
        )

        #expect(run.status == 0, "\(run.output)")
        for text in filterCase.present {
            #expect(run.output.contains(text), "missing \(text) in:\n\(run.output)")
        }
        for text in filterCase.absent {
            #expect(!run.output.contains(text), "unexpected \(text) in:\n\(run.output)")
        }
    }

    private static let shapes = """
        public protocol Shape {}
        public struct Square: Shape {}
        public struct Generated: Shape {}
        struct Helper: Shape {}
        """

    /// Writes into a fresh temporary directory `Types/Shapes.swift`; `Mods/App` importing
    /// `Foundation` and `Dispatch` and `Mods/Core` importing `Foundation`; and the package `Pkg`,
    /// whose target `App` depends on its target `Core`. Returns the directory.
    private static func makeProject() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftumlbridge-deps-filter-\(UUID().uuidString)")
        try write(shapes, to: root.appendingPathComponent("Types/Shapes.swift"))
        try write("import Foundation\nimport Dispatch\n", to: root.appendingPathComponent("Mods/App/App.swift"))
        try write("import Foundation\n", to: root.appendingPathComponent("Mods/Core/Core.swift"))
        try write("""
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Pkg", targets: [
                .target(name: "Core"),
                .target(name: "App", dependencies: ["Core"])
            ])
            """, to: root.appendingPathComponent("Pkg/Package.swift"))
        try write(shapes, to: root.appendingPathComponent("Pkg/Sources/Core/Shapes.swift"))
        try write(
            "import Foundation\nimport Core\npublic struct Circle: Shape {}\n",
            to: root.appendingPathComponent("Pkg/Sources/App/Circle.swift")
        )
        return root
    }

    private static func write(_ contents: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }
}
