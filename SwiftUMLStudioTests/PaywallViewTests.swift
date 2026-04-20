import Foundation
import StoreKit
import SwiftUI
import Testing
import ViewInspector
@testable import SwiftUMLStudio

// The `MockSubscriptionProvider` used here is defined in
// `SubscriptionManagerTests.swift`.

// MARK: - PaywallView

@Suite("PaywallView")
@MainActor
struct PaywallViewTests {

    private func makeView(
        purchaseError: String? = nil
    ) -> PaywallView<MockSubscriptionProvider> {
        let manager = MockSubscriptionProvider()
        manager.purchaseError = purchaseError
        return PaywallView(subscriptionManager: manager)
    }

    @Test("renders upgrade header and subtitle")
    func rendersHeader() throws {
        let strings = try makeView().inspect()
            .findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("Upgrade to Pro"))
        #expect(strings.contains("Unlock the full power of SwiftUML Studio"))
    }

    @Test("feature list renders all five PaywallFeature entries")
    func rendersFeatureList() throws {
        let strings = try makeView().inspect()
            .findAll(ViewType.Text.self).map { try $0.string() }
        for feature in PaywallFeature.all {
            #expect(strings.contains(feature.title))
            #expect(strings.contains(feature.description))
        }
    }

    @Test("shows \"Loading plans…\" when products list is empty")
    func emptyProductsShowsLoading() throws {
        let strings = try makeView().inspect()
            .findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("Loading plans…"))
    }

    @Test("Restore Purchases and Not Now buttons are present")
    func restoreAndDismissButtons() throws {
        let buttons = try makeView().inspect().findAll(ViewType.Button.self)
        let labels = buttons.compactMap { button -> String? in
            try? button.labelView().text().string()
        }
        #expect(labels.contains("Restore Purchases"))
        #expect(labels.contains("Not Now"))
    }

    @Test("error banner renders when purchaseError is set")
    func errorBannerShown() throws {
        let view = makeView(purchaseError: "network failed")
        let strings = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("network failed"))
    }

    @Test("error banner is hidden when purchaseError is nil")
    func errorBannerHidden() throws {
        let strings = try makeView().inspect()
            .findAll(ViewType.Text.self).map { try $0.string() }
        #expect(strings.contains("network failed") == false)
    }
}
