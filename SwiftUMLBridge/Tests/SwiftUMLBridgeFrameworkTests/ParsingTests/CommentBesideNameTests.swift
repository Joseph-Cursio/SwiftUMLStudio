import Foundation
import Testing
@testable import SwiftUMLBridgeFramework

/// A comment is trivia, not part of the name beside it: `var tag: String // note` declares a
/// `String`, and a comment line above `Store.shared.load()` does not change its receiver (#128).
/// Each source is read against itself with every comment removed, which is read as it always was.
@Suite("A comment beside a name is not part of it")
struct CommentBesideNameTests {

    /// `source` with every comment removed. A comment line becomes an empty line, so nothing moves
    /// to another line.
    private func uncommented(_ source: String) -> String {
        source.replacingOccurrences(of: #" *(//[^\n]*|/\*.*?\*/)"#, with: "", options: .regularExpression)
    }

    // MARK: - ER

    @Test("an ER property's type ends before the comment after it")
    func erPropertyType() {
        let source = """
            @Model final class Owner {
                var name: String = ""
                var pets: [Pet] = [] // every pet
            }
            @Model final class Pet {
                var tag: String // note
                var owner: Owner? // may be nil
                var nickname: String? /* if any */
            }
            """
        let model = ERModelExtractor.extract(from: source)
        let control = ERModelExtractor.extract(from: uncommented(source))
        #expect(control.relationships.map(\.label).sorted() == ["owner", "pets"])
        #expect(control.entities.flatMap(\.attributes).map(\.type) == ["String", "String", "String"])
        #expect(model == control)
    }

    @Test("@Model, @Transient and @Attribute are read without the comment beside them")
    func erAttributeNames() {
        let source = """
            @Model // persisted
            final class Item {
                var title: String = ""
                @Transient // recomputed on load
                var cache: String = ""
                @Attribute(.externalStorage /* was .unique */) var cover: String = ""
                @Attribute /* the business key */ (.unique) var code: String = ""
            }
            """
        let model = ERModelExtractor.extract(from: source)
        let control = ERModelExtractor.extract(from: uncommented(source))
        let attributes = control.entities.flatMap(\.attributes)
        #expect(control.entities.map(\.name) == ["Item"])
        #expect(attributes.map(\.name) == ["title", "cache", "cover", "code"])
        #expect(attributes.map(\.isTransient) == [false, true, false, false])
        #expect(attributes.map(\.isUnique) == [false, false, false, true])
        #expect(model == control)
    }

    @Test("@Relationship is read without the comment after its name")
    func erRelationshipName() {
        let source = """
            @Model final class Author {
                var name: String = ""
                @Relationship /* owns */ (inverse: \\Book.writer) var books: [Book] = []
            }
            @Model final class Book {
                var title: String = ""
                var writer: Author?
            }
            """
        let model = ERModelExtractor.extract(from: source)
        let control = ERModelExtractor.extract(from: uncommented(source))
        #expect(control.relationships.map(\.label) == ["books"])
        #expect(model == control)
    }

    // MARK: - State machines

    @Test("a state property's type ends before the comment after it")
    func stateProperty() {
        let source = """
            enum Light { case red, green }
            final class Lamp {
                var state: Light // current
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .red
                    }
                }
            }
            """
        let machines = StateMachineExtractor.extract(from: source)
        let control = StateMachineExtractor.extract(from: uncommented(source))
        #expect(control.map(\.identifier) == ["Lamp.Light"])
        #expect(machines == control)
    }

    @Test("an assignment to self.state beside a comment is a transition")
    func selfStateBesideComment() {
        let source = """
            enum Light { case red, green }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch self.state {
                    case .red:
                        // go
                        self.state = .green
                    case .green:
                        self // this lamp
                            .state = .red
                    }
                }
            }
            """
        let machines = StateMachineExtractor.extract(from: source)
        let control = StateMachineExtractor.extract(from: uncommented(source))
        #expect(control.flatMap(\.transitions).map { "\($0.from) -> \($0.toState)" }
            == ["red -> green", "green -> red"])
        #expect(machines == control)
    }

    // MARK: - Call receivers

    @Test("a call's receiver is read without a comment beside it")
    func receiver() {
        let source = """
            struct Screen {
                func start() {
                    // warm the cache
                    Store.shared.load()
                    Store.shared // the singleton
                        .load()
                    // then refresh
                    self.refresh()
                    self // this screen
                        .refresh()
                    self() // through callAsFunction
                        .refresh()
                }
            }
            """
        let edges = CallGraphExtractor.extract(from: source).edges
        let control = CallGraphExtractor.extract(from: uncommented(source)).edges
        #expect(control.map { "\($0.calleeType ?? "unresolved").\($0.calleeMethod)" }
            == ["Store.shared.load", "Store.shared.load", "Screen.refresh", "Screen.refresh", "Screen.refresh",
                "Screen.self"])
        #expect(edges == control)
    }
}
