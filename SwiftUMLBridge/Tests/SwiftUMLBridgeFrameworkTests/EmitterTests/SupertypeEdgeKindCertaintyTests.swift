import Testing
@testable import SwiftUMLBridgeFramework

/// When PlantUML, Mermaid and Nomnoml are sure a supertype's name means a protocol, so its edge
/// is a conformance. Imports are not tracked, so among same-named types of other modules the
/// lookup can only guess which one a writer means: such an edge is named as for a type it cannot
/// tell, `inherits`, unless it ends on that protocol's own box, whose shape says what it is
/// anyway. Each file passes `swiftc -typecheck` with the modules it imports.
@Suite("Text formats name a supertype edge only after a kind they are sure of")
struct SupertypeEdgeKindCertaintyTests {

    static let textFormats: [DiagramFormat] = [.plantuml, .mermaid, .nomnoml]
    static let realizes = (text: "<|..", nomnoml: "--:>")
    static let inherits = (text: "<|--", nomnoml: "-:>")

    /// A file of `module`, `nil` for sources read without their package.
    struct File {
        let module: String?
        let path: String
        let source: String
    }

    /// The items of `files`, each parsed into its module and stamped as declared in its own file.
    private func parsed(_ files: [File]) throws -> [SyntaxStructure] {
        try files.flatMap { file in
            let items = try #require(SyntaxStructure.create(from: file.source, module: file.module)?.substructure)
            func stamp(_ item: SyntaxStructure) {
                item.sourceLocation = SourceLocation(filePath: file.path, line: 1, column: 1)
                item.substructure?.forEach(stamp)
            }
            items.forEach(stamp)
            return items
        }
    }

    /// Every line `format` writes for `items`, with the types named `excluded` hidden.
    private func lines(
        _ items: [SyntaxStructure], _ format: DiagramFormat, excluding excluded: [String] = []
    ) -> [String] {
        let configuration = Configuration(elements: ElementOptions(exclude: excluded), format: format)
        return DiagramScript(items: items, configuration: configuration).text.split(separator: "\n").map(String.init)
    }

    /// The edge from `child` to `parent` as each format writes it: PlantUML and Mermaid
    /// `parent arrow child : label`, Nomnoml `[child] arrow label [parent]`.
    private func edgeLine(_ format: DiagramFormat, _ parent: String, _ arrow: (text: String, nomnoml: String),
                          _ child: String, _ label: String) -> String {
        format == .nomnoml
            ? "[\(child)] \(arrow.nomnoml) \(label) [\(parent)]" : "\(parent) \(arrow.text) \(child) : \(label)"
    }

    static let alphaProtocol = File(
        module: "Alpha", path: "Alpha/Service.swift", source: "public protocol Service { func onlyAlpha() }"
    )
    static let betaClass = File(
        module: "Beta", path: "Beta/Service.swift",
        source: "open class Service { public init() {}\n public func onlyBeta() {} }"
    )

    // MARK: - Unsure

    /// The nearest `Service` to App is Alpha's, recorded first, but App imports Beta's class.
    @Test("an edge to a name two other modules hide as different kinds is not named after a guess",
          arguments: textFormats)
    func ambiguousKindAcrossModules(format: DiagramFormat) throws {
        let impl = File(module: "App", path: "App/Impl.swift",
                        source: "import Beta\nfinal class Impl: Service { func use() { onlyBeta() } }")
        let items = try parsed([Self.alphaProtocol, Self.betaClass, impl])
        #expect(lines(items, format, excluding: ["Service"])
            .contains(edgeLine(format, "Service", Self.inherits, "Impl", "inherits")))
    }

    /// App's own typealias is sure to be the one `Base` means, but the name it aliases is the
    /// same guess between Alpha's and Beta's `Service`. That alias's sureness counted for the
    /// whole name, so the edge was named after Alpha's protocol.
    @Test("an edge through the writer's own typealias to a guessed type is not named after the guess",
          arguments: textFormats)
    func ambiguousKindThroughOwnAlias(format: DiagramFormat) throws {
        let impl = File(module: "App", path: "App/Impl.swift", source: """
            import Beta
            typealias Base = Service
            final class Impl: Base { func use() { onlyBeta() } }
            """)
        let items = try parsed([Self.alphaProtocol, Self.betaClass, impl])
        #expect(lines(items, format, excluding: ["Service"])
            .contains(edgeLine(format, "Service", Self.inherits, "Impl", "inherits")))
    }

    /// Beta's `Service` is a typealias of a type outside the diagram, so of no kind the diagram
    /// knows: no sign App means Alpha's protocol.
    @Test("an edge to a name another module aliases to an outside type is not named after a guess",
          arguments: textFormats)
    func ambiguousKindBesideOutsideAlias(format: DiagramFormat) throws {
        let betaAlias = File(module: "Beta", path: "Beta/Service.swift",
                             source: "import Foundation\npublic typealias Service = NSObject")
        let impl = File(module: "App", path: "App/Impl.swift",
                        source: "import Beta\nimport Foundation\nfinal class Impl: Service {}")
        let items = try parsed([Self.alphaProtocol, betaAlias, impl])
        #expect(lines(items, format, excluding: ["Service"])
            .contains(edgeLine(format, "Service", Self.inherits, "Impl", "inherits")))
    }

    // MARK: - Ends on a protocol's box

    /// Read without their package, the three files have no modules to tell apart, so which
    /// `Service` `Impl` means is a guess. It ends on Alpha's drawn protocol, so its edge is a
    /// conformance, as that box's shape has it, not an inheritance to a protocol.
    @Test("an edge that ends on a drawn protocol is a conformance though the name was a guess",
          arguments: textFormats)
    func guessEndingOnDrawnProtocol(format: DiagramFormat) throws {
        let impl = File(module: nil, path: "App/Impl.swift",
                        source: "import Alpha\nfinal class Impl: Service { func onlyAlpha() {} }")
        let files = [Self.alphaProtocol, Self.betaClass].map { File(module: nil, path: $0.path, source: $0.source) }
        #expect(lines(try parsed(files + [impl]), format)
            .contains(edgeLine(format, "Service", Self.realizes, "Impl", "conforms to")))
    }

    // MARK: - Cost

    static let libraries = 200

    /// `libraries` modules, each aliasing its own protocol as `Base`, and an App module whose
    /// `libraries` types each conform to `Base`.
    static func aliasedProtocols(cyclicLast: Bool = false) -> [File] {
        let modules = (0..<libraries).map { index in
            let isCyclic = cyclicLast && index == libraries - 1
            return File(module: "Lib\(index)", path: "Lib\(index)/Base.swift",
                        source: isCyclic ? "public typealias Base = Base"
                            : "public protocol Model {}\npublic typealias Base = Model")
        }
        let writers = (0..<libraries).map { index in
            File(module: "App", path: "App/Writer\(index).swift", source: "import Lib0\nstruct Writer\(index): Base {}")
        }
        return modules + writers
    }

    /// The bound is for a debug build under load. Checking every candidate's typealias again for
    /// each edge took seconds, growing with the cube of the modules.
    @Test("many modules aliasing a protocol of one name are checked once each")
    func manyAliasedProtocols() throws {
        let items = try parsed(Self.aliasedProtocols())
        var text: [String] = []
        let elapsed = ContinuousClock().measure { text = lines(items, .plantuml) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #expect(text.contains(edgeLine(.plantuml, "Model", Self.realizes, "Writer7", "conforms to")))
    }

    /// `libraries` directories read without their package, each declaring a protocol nested in
    /// an extension of its own `Outer` and aliasing it as `P`, and one writer. Each alias's target
    /// was looked up again for every alias, and each lookup asked every `Outer.Q` what its
    /// extension extends, another lookup: cubic in the directories, for a single edge.
    @Test("many aliases of protocols nested in extensions are checked once each")
    func manyAliasesOfNestedProtocols() throws {
        let files = (0..<Self.libraries).flatMap { index in [
            File(module: nil, path: "Lib\(index)/Outer.swift",
                 source: "struct Outer {}\nextension Outer { protocol Q {} }"),
            File(module: nil, path: "Lib\(index)/Alias.swift", source: "typealias P = Outer.Q")
        ] } + [File(module: nil, path: "Lib0/Writer.swift", source: "struct Writer: P {}")]
        let items = try parsed(files)
        var text: [String] = []
        let elapsed = ContinuousClock().measure { text = lines(items, .plantuml) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #expect(text.contains(edgeLine(.plantuml, "Outer.Q", Self.realizes, "Writer", "conforms to")))
    }

    /// 600 directories read without their package, each with a chain of seven typealiases to
    /// its own protocol in one file, and one writer. Each alias of a link was checked by a lookup
    /// among every same-named one, though its own file declares the next.
    @Test("many alias chains, each in one file, are checked once each")
    func manyAliasChainsInOneFile() throws {
        let chain = (0..<7).map { "typealias A\($0) = \($0 == 6 ? "Proto" : "A\($0 + 1)")" }.joined(separator: "\n")
            + "\nprotocol Proto {}"
        let files = (0..<600).map { File(module: nil, path: "Dir\($0)/Chain.swift", source: chain) }
            + [File(module: nil, path: "Dir0/Writer.swift", source: "struct Writer: A0 {}")]
        let items = try parsed(files)
        var text: [String] = []
        let elapsed = ContinuousClock().measure { text = lines(items, .plantuml) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #expect(text.contains(edgeLine(.plantuml, "Proto", Self.realizes, "Writer", "conforms to")))
    }

    /// 600 directories read without their package, each with a chain of typealiases written
    /// through a type's members, `typealias A0 = NS.A1` and `struct NS { typealias A1 = NS.A2 ... }`,
    /// to a protocol in a file of its own, and one writer. A dotted name was looked up among every
    /// same-named alias, and each alias walked the rest of its chain again, to the protocol.
    @Test("many alias chains through a type's members are checked once each")
    func manyDottedAliasChains() throws {
        let members = (1..<8).map { "    typealias A\($0) = \($0 == 7 ? "Proto" : "NS.A\($0 + 1)")" }
            .joined(separator: "\n")
        let files = (0..<600).flatMap { index in [
            File(module: nil, path: "Dir\(index)/Alias.swift", source: "typealias A0 = NS.A1"),
            File(module: nil, path: "Dir\(index)/NS.swift", source: "struct NS {\n\(members)\n}"),
            File(module: nil, path: "Dir\(index)/Proto.swift", source: "protocol Proto {}")
        ] } + [File(module: nil, path: "Dir0/Writer.swift", source: "struct Writer: A0 {}")]
        let items = try parsed(files)
        var text: [String] = []
        let elapsed = ContinuousClock().measure { text = lines(items, .plantuml) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #expect(text.contains(edgeLine(.plantuml, "Proto", Self.realizes, "Writer", "conforms to")))
    }

    /// One module's `Base` is a cycle, which Swift rejects, so comes to no kind at all: no sign
    /// App means a protocol. The edge ends on no box, Lib0's protocol being hidden.
    @Test("a cyclic typealias among the candidates ends, unsure of the kind")
    func cyclicAliasAmongCandidates() throws {
        let items = try parsed(Self.aliasedProtocols(cyclicLast: true))
        var text: [String] = []
        let elapsed = ContinuousClock().measure { text = lines(items, .plantuml, excluding: ["Model"]) }
        #expect(elapsed < .seconds(2), "\(elapsed)")
        #expect(text.contains(edgeLine(.plantuml, "Model", Self.inherits, "Writer7", "inherits")))
    }
}
