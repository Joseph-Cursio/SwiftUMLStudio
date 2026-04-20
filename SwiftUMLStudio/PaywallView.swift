import StoreKit
import SwiftUI

nonisolated struct PaywallFeature: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String

    static let all: [PaywallFeature] = [
        PaywallFeature(
            title: "Sequence Diagrams",
            description: "Trace execution flows through your code"
        ),
        PaywallFeature(
            title: "Dependency Graphs",
            description: "See how your modules depend on each other"
        ),
        PaywallFeature(
            title: "PlantUML & Mermaid Export",
            description: "Copy or save diagram markup"
        ),
        PaywallFeature(
            title: "Format Selection",
            description: "Switch between PlantUML and Mermaid"
        ),
        PaywallFeature(
            title: "Unlimited Projects",
            description: "Explore as many codebases as you want"
        )
    ]
}

struct PaywallView<Manager: SubscriptionProviding>: View {
    let subscriptionManager: Manager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            header
            featureList
            purchaseButtons
            restoreLink
            if let error = subscriptionManager.purchaseError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(32)
        .frame(width: 400)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("Upgrade to Pro")
                .font(.title.bold())
            Text("Unlock the full power of SwiftUML Studio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PaywallFeature.all) { feature in
                featureRow(feature.title, description: feature.description)
            }
        }
        .padding(.horizontal, 8)
    }

    private func featureRow(_ title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var purchaseButtons: some View {
        VStack(spacing: 8) {
            ForEach(subscriptionManager.products, id: \.id) { product in
                Button {
                    Task { await subscriptionManager.purchase(product) }
                } label: {
                    Text("\(product.displayName) — \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if subscriptionManager.products.isEmpty {
                Text("Loading plans…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private var restoreLink: some View {
        HStack {
            Button("Restore Purchases") {
                Task { await subscriptionManager.restorePurchases() }
            }
            .buttonStyle(.link)
            .font(.caption)

            Spacer()

            Button("Not Now") { dismiss() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}
