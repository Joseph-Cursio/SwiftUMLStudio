import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// How the walks along a chain of typealiases that #248 made run to its end tell a cycle from a
/// legal chain, and what they cost: each source here builds with swiftc.
@Suite("A walk along a chain of typealiases")
struct AliasChainWalkTests {
    /// Whether an extension's type is the project's follows only a name's leading alias, keeping
    /// the parts after it, so one alias may lead the name twice with other parts after it:
    /// `D.Inner` is `Outer.Inner`, which is `D.Y`, which is `Outer.Y`. Taken for a cycle, the
    /// extension was judged of a type outside the diagram, and `W`'s edge was lost.
    @Test("an alias leading a name again, before another member, is no cycle",
          arguments: [true, false], (["App", nil] as [String?]))
    func aliasLeadingAgain(showNestedTypes: Bool, module: String?) throws {
        let source = """
            typealias D = Outer
            struct Outer {
                typealias Inner = D.Y
                struct Y {}
            }
            extension D.Inner {
                typealias Desc = CustomStringConvertible
            }
            extension CustomStringConvertible { func describe() {} }
            struct W: D.Inner.Desc { var description: String { "" } }
            """
        let elements = ElementOptions(showNestedTypes: showNestedTypes)
        let items = try moduleQualifiedItems([(module: module, source: source)])
        let text = DiagramScript(items: items, configuration: Configuration(elements: elements)).text
        #expect(ClassDiagramIds.lines(of: text, containing: "<|") == ["CustomStringConvertible <|-- W : inherits"])
    }

    /// Hidden nested types give each link two readings, a hidden member and the target as
    /// written, and a name two readings come to is judged once, so a chain of 200 links whose
    /// every link reads two ways costs a step a name. Judged once a path, it doubled a link.
    @Test("links that each read two ways are judged a name at a time")
    func linksReadingTwoWays() throws {
        let links = (2...200).map { "        typealias X\($0) = S.X\($0 - 1)" }.joined(separator: "\n")
        let aliases = "        typealias X1 = Date\n\(links)"
        let source = "import Foundation\nstruct S {\n\(aliases)\n    struct S {\n\(aliases)\n    }\n}\n"
            + "extension S.X200 { typealias Q = Codable }\nstruct Z: S.X200.Q {}"
        let items = try moduleQualifiedItems([(module: nil, source: source)])
        let elements = ElementOptions(showNestedTypes: false)
        var text = ""
        let seconds = ThreadCPUClock.seconds {
            text = DiagramScript(items: items, configuration: Configuration(elements: elements)).text
        }
        #expect(seconds < 2, "\(seconds)")
        #expect(ClassDiagramIds.lines(of: text, containing: "<|") == ["Codable <|-- Z : inherits"])
    }

    /// The same, for extensions merged into the type they extend, which judges each one's type.
    @Test("a merged extension of a chain whose links read two ways is judged a name at a time")
    func mergedLinksReadingTwoWays() throws {
        let links = (1..<200).map { "    typealias A\($0) = N.A\($0 + 1)" }.joined(separator: "\n")
        let aliases = "\(links)\n    typealias A200 = Int"
        let source = "struct N {\n\(aliases)\n    struct N {\n\(aliases)\n    }\n}\n"
            + "extension N.A1 { typealias Z = Int.Words }\nextension N.A1.Z { func probe() {} }"
        let items = try moduleQualifiedItems([(module: nil, source: source)])
        let elements = ElementOptions(showNestedTypes: false, showExtensions: .merged)
        var text = ""
        let seconds = ThreadCPUClock.seconds {
            text = DiagramScript(items: items, configuration: Configuration(elements: elements)).text
        }
        #expect(seconds < 2, "\(seconds)")
        #expect(text.contains("probe"))
    }

    /// A writer at every link of a 2,000-link chain: what each alias comes to is kept, so the
    /// chain is walked once, not once for each writer.
    @Test("writers along a long chain walk it once")
    func writersAlongChain() throws {
        let links = (2...2_000).map { "typealias A\($0) = A\($0 - 1)" }.joined(separator: "\n")
        let writers = (1...2_000).map { "struct W\($0): A\($0) {}" }.joined(separator: "\n")
        let source = "protocol P1 {}\ntypealias A1 = P1\n\(links)\n\(writers)"
        let items = try moduleQualifiedItems([(module: "App", source: source)])
        var text = ""
        let seconds = ThreadCPUClock.seconds { text = DiagramScript(items: items, configuration: Configuration()).text }
        #expect(seconds < 2, "\(seconds)")
        #expect(ClassDiagramIds.lines(of: text, containing: "P1 <|.. W").count == 2_000)
    }

    /// A walk that reads no module qualifier, which tells whether a name means a type only
    /// through one, starts reading them at sugar. An alias it followed before may then come to
    /// another type, so coming back to one is no cycle, and taking it for one kept "nothing" for
    /// lookups that read modules: `extension [Int].Q` was drawn apart from `Foo.T`'s other
    /// extension or merged into it by which came first.
    @Test("a walk that starts reading modules at sugar keeps no cycle it did not meet",
          arguments: [false, true])
    func readingModulesAtSugar(reversed: Bool) throws {
        let extensions = ["extension Lib.Foo.X { func first() {} }", "extension [Int].Q { func second() {} }"]
        let app = """
            import Lib
            extension Lib.Foo { typealias X = T }
            typealias T = [Int].Q
            extension Array { typealias Q = Lib.Foo.X }
            struct W1: Lib.Foo.X {}
            struct W2: T {}
            """ + "\n" + (reversed ? extensions.reversed() : extensions).joined(separator: "\n")
        let items = try moduleQualifiedItems([
            (module: "Lib", source: "public struct Foo { public protocol T {} }"), (module: "App", source: app)
        ])
        let elements = ElementOptions(showExtensions: .merged)
        let text = DiagramScript(items: items, configuration: Configuration(elements: elements)).text
        let protocolBox = try #require(text.components(separatedBy: "\n}").first { $0.contains("as Foo.T") })
        #expect(protocolBox.contains("first") && protocolBox.contains("second"), "\(text)")
        #expect(!text.contains("Array.Q"), "\(text)")
    }
}
