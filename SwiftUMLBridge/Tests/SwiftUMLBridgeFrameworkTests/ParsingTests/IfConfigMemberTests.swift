import Testing
@testable import SwiftUMLBridgeFramework

// An `#if` block's clauses are read like the rest of the type, as the class diagram reads them
// (#135). Most tests run their source as written (`ifConfig → true`) and with every `#if`
// replaced by its first clause (`ifConfig → false`), which is the file the compiler sees when
// each condition holds. The second case is the control.

/// `text` with each `#if` line and `#endif` line removed, and each `#else` or `#elseif` clause
/// dropped. Not nested; the sources passed to it never nest.
private func source(_ text: String, ifConfig: Bool) -> String {
    guard !ifConfig else { return text }
    var kept: [Substring] = []
    var skipping = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let directive = line.trimmingCharacters(in: .whitespaces)
        if directive.hasPrefix("#if") { continue }
        if directive.hasPrefix("#else") || directive.hasPrefix("#elseif") {
            skipping = true
            continue
        }
        if directive.hasPrefix("#endif") {
            skipping = false
            continue
        }
        if !skipping { kept.append(line) }
    }
    return kept.joined(separator: "\n")
}

@Suite("ER declarations inside #if are read")
struct IfConfigERTests {

    private func flags(_ attributes: String) -> [String] {
        ERModelExtractor.extract(from: """
            @Model final class User {
                \(attributes)
                var email: String = ""
            }
            """).entities.flatMap(\.attributes)
            .map { "\($0.name) unique=\($0.isUnique) pk=\($0.isPrimaryKey) transient=\($0.isTransient)" }
    }

    // MARK: - SwiftData

    @Test("an @Model property inside #if is an attribute or a relationship", arguments: [true, false])
    func modelPropertyInIfConfig(ifConfig: Bool) {
        let model = ERModelExtractor.extract(from: source("""
            @Model final class Owner {
                var name: String = ""
                #if DEBUG
                var debugNote: String = ""
                var pets: [Pet] = []
                #endif
            }
            @Model final class Pet {
                var tag: String = ""
            }
            """, ifConfig: ifConfig))
        let attributes = model.entities.flatMap { entity in entity.attributes.map { "\(entity.name).\($0.name)" } }
        let relationships = model.relationships.map { "\($0.from).\($0.label) -> \($0.toEntity)" }
        #expect(attributes == ["Owner.name", "Owner.debugNote", "Pet.tag"])
        #expect(relationships == ["Owner.pets -> Pet"])
    }

    @Test("an @Model property inside nested #if blocks is read in every clause")
    func nestedIfConfig() {
        let attributes = ERModelExtractor.extract(from: """
            @Model final class Owner {
                var name: String = ""
                #if os(macOS)
                #if DEBUG
                var debugNote: String = ""
                #endif
                #elseif os(iOS)
                var phoneNote: String = ""
                #endif
            }
            """).entities.flatMap(\.attributes).map(\.name)
        #expect(attributes == ["name", "debugNote", "phoneNote"])
    }

    @Test("a property declared in two clauses is one, from the first")
    func propertyInTwoClauses() {
        let attributes = ERModelExtractor.extract(from: """
            @Model final class Settings {
                #if DEBUG
                var level: Int = 3
                #else
                var level: Int64 = 0
                #endif
            }
            """).entities.flatMap(\.attributes).map { "\($0.name): \($0.type)" }
        #expect(attributes == ["level: Int"])
    }

    @Test("@Attribute(.unique) inside #if marks the property unique", arguments: [true, false])
    func uniqueAttributeInIfConfig(ifConfig: Bool) {
        let observed = flags(source("""
            #if !LEGACY_SCHEMA
            @Attribute(.unique)
            #endif
            """, ifConfig: ifConfig))
        #expect(observed == ["email unique=true pk=true transient=false"])
    }

    /// `@Model` reads only a property's first `@Attribute` (#140). Under `#if`, that is the first
    /// one of each choice of clauses, and the property is unique when any of them lists `.unique`.
    @Test("the first @Attribute of each clause is read", arguments: [
        ("#if LEGACY_SCHEMA\n@Attribute(.externalStorage)\n#else\n@Attribute(.unique)\n#endif", true),
        ("#if DEBUG\n@Attribute(.spotlight)\n#endif\n@Attribute(.unique)", true),
        ("@Attribute(.spotlight)\n#if DEBUG\n@Attribute(.unique)\n#endif", false),
        ("#if DEBUG\n@Attribute(.spotlight)\n#else\n@Attribute(.externalStorage)\n#endif\n@Attribute(.unique)", false)
    ])
    func firstAttributeOfEachClause(attributes: String, unique: Bool) {
        #expect(flags(attributes) == ["email unique=\(unique) pk=\(unique) transient=false"])
    }

    @Test("@Transient inside #if marks the property transient", arguments: [true, false])
    func transientInIfConfig(ifConfig: Bool) {
        let observed = flags(source("""
            #if !LEGACY_SCHEMA
            @Transient
            #endif
            """, ifConfig: ifConfig))
        #expect(observed == ["email unique=false pk=false transient=true"])
    }

    @Test("@Relationship(inverse:) inside #if names its inverse", arguments: [
        "#if !LEGACY_SCHEMA\n@Relationship(inverse: \\Book.writer)\n#endif",
        "#if LEGACY_SCHEMA\n@Relationship(deleteRule: .cascade)\n#else\n@Relationship(inverse: \\Book.writer)\n#endif"
    ])
    func relationshipAttributeInIfConfig(attribute: String) {
        for ifConfig in [true, false] {
            let relationships = ERModelExtractor.extract(from: source("""
                @Model final class Author {
                    var name: String = ""
                    \(attribute)
                    var books: [Book] = []
                }
                @Model final class Book {
                    var title: String = ""
                    var writer: Author?
                }
                """, ifConfig: ifConfig)).relationships
                .map { "\($0.from).\($0.label) -> \($0.toEntity) inverse=\($0.inverseLabel ?? "nil")" }
            // The control of the second argument keeps only `@Relationship(deleteRule:)`.
            let expected = ifConfig || attribute.hasPrefix("#if !")
                ? ["Author.books -> Book inverse=writer"]
                : ["Author.books -> Book inverse=nil", "Book.writer -> Author inverse=nil"]
            #expect(relationships == expected, "ifConfig: \(ifConfig)")
        }
    }

    @Test("@Model inside #if marks an entity", arguments: [true, false])
    func modelAttributeInIfConfig(ifConfig: Bool) {
        let entities = ERModelExtractor.extract(from: source("""
            #if canImport(SwiftData)
            @Model
            #endif
            final class Item {
                var title: String = ""
            }
            """, ifConfig: ifConfig)).entities.map(\.name)
        #expect(entities == ["Item"])
    }

    // MARK: - GRDB and SQLite.swift

    @Test("a GRDB record's column inside #if is a column", arguments: [true, false])
    func grdbColumnInIfConfig(ifConfig: Bool) {
        let columns = PersistenceSchemaExtractor.extract(from: source("""
            struct Player: FetchableRecord, PersistableRecord {
                var id: Int64
                var name: String
                #if DEBUG
                var debugScore: Int
                #else
                var debugScore: Int64
                #endif
            }
            """, ifConfig: ifConfig)).entities.flatMap(\.attributes).map { "\($0.name): \($0.type)" }
        #expect(columns == ["id: Int64", "name: String", "debugScore: Int"])
    }

    @Test("a SQLite.swift column inside #if is a column", arguments: [true, false])
    func sqliteColumnInIfConfig(ifConfig: Bool) {
        let model = PersistenceSchemaExtractor.extract(from: source("""
            enum Schema {
                static let users = Table("users")
                static let id = Expression<Int64>("id")
                #if DEBUG
                static let note = Expression<String>("debug_note")
                #else
                static let note = Expression<String?>("debug_note")
                #endif
            }
            """, ifConfig: ifConfig))
        #expect(model.entities.map(\.name) == ["users"])
        #expect(model.entities.flatMap(\.attributes).map { "\($0.name): \($0.type)" }
                == ["id: Int64", "debug_note: String"])
    }

    /// Two clauses that each declare `users` declare one table. Read as two, the container would
    /// hold two tables and give neither its columns.
    @Test("a SQLite.swift table declared in two clauses is one table, from the first", arguments: [
        ("users_debug", "users"),
        ("users", "users")
    ])
    func sqliteTableInTwoClauses(debugName: String, releaseName: String) {
        let model = PersistenceSchemaExtractor.extract(from: """
            enum Schema {
                #if DEBUG
                static let users = Table("\(debugName)")
                #else
                static let users = Table("\(releaseName)")
                #endif
                static let id = Expression<Int64>("id")
            }
            """)
        #expect(model.entities.map(\.name) == [debugName])
        #expect(model.entities.flatMap(\.attributes).map(\.name) == ["id"])
    }

}

@Suite("State-machine declarations inside #if are read")
struct IfConfigStateMachineTests {

    @Test("an assignment repeated in each #if clause is one transition", arguments: [true, false])
    func transitionInEachClause(ifConfig: Bool) throws {
        let machine = try #require(StateMachineExtractor.extract(from: source("""
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        #if DEBUG
                        print("debug: back to red")
                        state = .red
                        #else
                        state = .red
                        #endif
                    }
                }
            }
            """, ifConfig: ifConfig)).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> red"])
    }

    @Test("an assignment repeated in both branches of an if is one transition")
    func transitionInEachIfBranch() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                var verbose = false
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        if verbose {
                            print("back to red")
                            state = .red
                        } else {
                            state = .red
                        }
                    }
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> red"])
    }

    @Test("different assignments in the clauses are each a transition")
    func differentTransitionsInClauses() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Light { case red, green, amber }
            final class Lamp {
                var state: Light = .red
                func next() {
                    switch state {
                    case .red: state = .green
                    case .green: state = .amber
                    case .amber:
                        #if DEBUG
                        state = .green
                        #else
                        state = .red
                        #endif
                    }
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" }
                == ["red -> green", "green -> amber", "amber -> green", "amber -> red"])
    }

    @Test("a repeated assignment with no switch is one transition")
    func unknownSourceTransitionInEachClause() throws {
        let machine = try #require(StateMachineExtractor.extract(from: """
            enum Phase { case idle, running }
            final class Job {
                var phase: Phase = .idle
                func start() {
                    #if DEBUG
                    phase = .running
                    #else
                    phase = .running
                    #endif
                }
            }
            """).first)
        #expect(machine.transitions.map { "\($0.from) -> \($0.toState)" } == ["* -> running"])
    }

    @Test("an enum case inside #if is a state", arguments: [true, false])
    func enumCaseInIfConfig(ifConfig: Bool) throws {
        let machine = try #require(StateMachineExtractor.extract(from: source("""
            enum Phase {
                case idle, running
                #if DEBUG
                case done
                #else
                case done
                #endif
            }
            final class Job {
                var phase: Phase = .idle
                func step() {
                    switch phase {
                    case .idle: phase = .running
                    #if DEBUG
                    case .running: phase = .done
                    #endif
                    default: break
                    }
                }
            }
            """, ifConfig: ifConfig)).first)
        let states = machine.states.map { "\($0.name)\($0.isInitial ? " initial" : "")\($0.isFinal ? " final" : "")" }
        #expect(states == ["idle initial", "running", "done final"])
    }

    @Test("an enum case with associated values inside #if still rejects the enum", arguments: [true, false])
    func associatedValueCaseInIfConfig(ifConfig: Bool) {
        let machines = StateMachineExtractor.extract(from: source("""
            enum Phase {
                case idle, running
                #if DEBUG
                case failed(String)
                #endif
            }
            final class Job {
                var phase: Phase = .idle
                func step() {
                    switch phase {
                    case .idle: phase = .running
                    case .running: phase = .idle
                    #if DEBUG
                    case .failed: phase = .idle
                    #endif
                    }
                }
            }
            """, ifConfig: ifConfig)).map(\.identifier)
        #expect(machines.isEmpty)
    }
}
