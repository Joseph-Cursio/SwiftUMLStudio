import Foundation
@testable import SwiftUMLStudio
import Testing

@Suite("PaywallFeature.all")
struct PaywallFeatureTests {

    @Test("five Pro features are advertised")
    func count() {
        #expect(PaywallFeature.all.count == 5)
    }

    @Test("each feature has a non-empty title and description")
    func nonEmptyContent() {
        for feature in PaywallFeature.all {
            #expect(feature.title.isEmpty == false)
            #expect(feature.description.isEmpty == false)
        }
    }

    @Test("titles cover the expected Pro areas")
    func coversProAreas() {
        let titles = Set(PaywallFeature.all.map(\.title))
        #expect(titles.contains("Execution Flows"))
        #expect(titles.contains("Dependency Maps"))
        #expect(titles.contains("Share Your Diagrams"))
    }

    /// The paywall is the one Explorer-mode surface that names Pro features, so
    /// it must not leak UML or markup jargon at a non-developer (plan §3.4).
    @Test("no title leaks developer jargon at Explorer users")
    func titlesAvoidJargon() {
        let jargon = ["UML", "PlantUML", "Mermaid", "Sequence Diagram", "Dependency Graph"]
        for feature in PaywallFeature.all {
            for term in jargon {
                #expect(
                    feature.title.localizedCaseInsensitiveContains(term) == false,
                    "paywall title \"\(feature.title)\" leaks the developer term \"\(term)\""
                )
            }
        }
    }

    @Test("each feature identifier is unique")
    func uniqueIdentifiers() {
        let identifiers = Set(PaywallFeature.all.map(\.id))
        #expect(identifiers.count == PaywallFeature.all.count)
    }
}
