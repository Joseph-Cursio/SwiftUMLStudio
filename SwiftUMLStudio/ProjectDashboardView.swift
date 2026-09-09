import SwiftUI
import SwiftUMLBridgeFramework

struct ProjectDashboardView: View {
    let summary: ProjectSummary?
    let insights: [Insight]
    let suggestions: [DiagramSuggestion]
    let architectureDiff: ArchitectureDiff?
    let isProUnlocked: Bool
    let onSuggestionTap: (DiagramSuggestion) -> Void

    var body: some View {
        if let summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statsBar(summary: summary)
                    if isProUnlocked, let diff = architectureDiff {
                        ArchitectureDiffView(diff: diff)
                    }
                    TypeBreakdownGrid(summary: summary)
                    if !summary.moduleBreakdown.isEmpty {
                        ModuleBreakdownSection(modules: summary.moduleBreakdown)
                    }
                    if !insights.isEmpty {
                        InsightsSection(insights: insights)
                    }
                    if !suggestions.isEmpty {
                        suggestionsSection
                    }
                }
                .padding(24)
            }
            .accessibilityIdentifier("dashboardContent")
        } else {
            ContentUnavailableView(
                "No project loaded",
                systemImage: "folder",
                description: Text("Open a folder or Swift files to see project insights.")
            )
            .accessibilityIdentifier("dashboardEmpty")
        }
    }

    // MARK: - Stats Bar

    private func statsBar(summary: ProjectSummary) -> some View {
        HStack(spacing: 16) {
            StatCardView(value: summary.totalFiles, label: "Files", icon: "doc.text")
            StatCardView(value: summary.totalTypes, label: "Types", icon: "rectangle.3.group")
            StatCardView(value: summary.totalRelationships, label: "Relationships", icon: "arrow.triangle.branch")
            StatCardView(value: summary.entryPoints.count, label: "Methods", icon: "function")
            StatCardView(
                value: summary.stateMachines.count,
                label: "State Machines",
                icon: "arrow.triangle.2.circlepath"
            )
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Diagrams")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                ForEach(suggestions) { suggestion in
                    SuggestionCardView(suggestion: suggestion, onTap: onSuggestionTap)
                }
            }
        }
    }
}

// MARK: - Extracted Subviews

/// The insights list.
///
/// Takes the insights alone. The dashboard is handed `onSuggestionTap`, a fresh closure on every
/// update its parent runs, so the dashboard itself never compares equal — this does.
struct InsightsSection: View {
    let insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.headline)
            ForEach(insights) { insight in
                InsightRowView(insight: insight)
            }
        }
    }
}

struct StatCardView: View {
    let value: Int
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TypeBreakdownGrid: View {
    let summary: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type Breakdown")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(summary.typeBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { kind, count in
                    HStack {
                        Text(kind)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(count)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

struct ModuleBreakdownSection: View {
    let modules: [ModuleSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modules")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                ForEach(modules, id: \.name) { module in
                    ModuleCardView(module: module)
                }
            }
        }
        .accessibilityIdentifier("dashboardModuleBreakdown")
    }
}

struct ModuleCardView: View {
    let module: ModuleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(NativeDiagramGeometry.moduleColor(for: module.name))
                    .frame(width: 10, height: 10)
                Text(module.name)
                    .font(.body.bold())
                    .lineLimit(1)
                Spacer()
                Text(kindLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tertiary.opacity(0.4), in: Capsule())
            }
            HStack(spacing: 12) {
                ModuleStat(value: module.fileCount, label: "files")
                ModuleStat(value: module.typeCount, label: "types")
                ModuleStat(value: module.outgoingTargetDependencies, label: "deps")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var kindLabel: String {
        switch module.kind {
        case .library:    return "library"
        case .executable: return "executable"
        case .test:       return "test"
        case .other:      return "other"
        }
    }
}

private struct ModuleStat: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct InsightRowView: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundStyle(insightColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.body.bold())
                Text(insight.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private var insightColor: SwiftUI.Color {
        InsightRowView.color(for: insight.severity)
    }

    /// Maps an `Insight.Severity` to its dashboard row color.
    static func color(for severity: Insight.Severity) -> SwiftUI.Color {
        switch severity {
        case .info: .blue
        case .noteworthy: .orange
        case .warning: .red
        }
    }
}

struct SuggestionCardView: View {
    let suggestion: DiagramSuggestion
    let onTap: (DiagramSuggestion) -> Void

    var body: some View {
        Button {
            onTap(suggestion)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(suggestion.title)
                            .font(.body.bold())
                        if suggestion.requiresPro {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(suggestion.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
