import Foundation

struct Insight: Identifiable, Sendable {
    let identifier = UUID()
    let icon: String
    let title: String
    let description: String
    let severity: Severity

    var id: UUID { identifier }

    enum Severity {
        case info
        case noteworthy
        case warning
    }
}

nonisolated enum InsightEngine {
    static func generate(from summary: ProjectSummary) -> [Insight] {
        var insights: [Insight] = []
        appendWarnings(from: summary, to: &insights)
        appendStructureInsights(from: summary, to: &insights)
        appendFeatureInsights(from: summary, to: &insights)
        return insights
    }

    // MARK: - Warning-level insights

    private static func appendWarnings(from summary: ProjectSummary, to insights: inout [Insight]) {
        if !summary.cycleWarnings.isEmpty {
            let names = summary.cycleWarnings.prefix(3).joined(separator: ", ")
            let extra = summary.cycleWarnings.count > 3
                ? " and \(summary.cycleWarnings.count - 3) more" : ""
            insights.append(Insight(
                icon: "exclamationmark.triangle.fill",
                title: "Circular dependencies detected",
                description: "\(names)\(extra) are involved in dependency cycles.",
                severity: .warning
            ))
        }

        for top in summary.topConnectedTypes where top.connectionCount >= 5 {
            insights.append(Insight(
                icon: "link.circle.fill",
                title: "\(top.name) is a critical dependency",
                description: "Used by \(top.connectionCount) other types — changes here have wide impact.",
                severity: .noteworthy
            ))
        }
    }

    // MARK: - Structure insights

    private static func appendStructureInsights(from summary: ProjectSummary, to insights: inout [Insight]) {
        if summary.totalTypes > 0 {
            let parts = summary.typeBreakdown
                .sorted { $0.value > $1.value }
                .map { "\($0.value) \($0.key.lowercased())" }
                .joined(separator: ", ")
            insights.append(Insight(
                icon: "chart.pie.fill",
                title: "Project composition",
                description: "Your project has \(parts).",
                severity: .info
            ))
        }

        let protocolCount = summary.typeBreakdown["Protocols"] ?? 0
        if protocolCount >= 3 {
            insights.append(Insight(
                icon: "checklist",
                title: "\(protocolCount) protocols found",
                description: "See how your types conform to shared interfaces.",
                severity: .info
            ))
        }

        if summary.totalRelationships == 0 && summary.totalTypes > 0 {
            insights.append(Insight(
                icon: "circle.dashed",
                title: "No type relationships found",
                description: "Your types appear to be independent — no inheritance or conformance detected.",
                severity: .info
            ))
        }
    }

    // MARK: - Feature insights

    private static func appendFeatureInsights(from summary: ProjectSummary, to insights: inout [Insight]) {
        if !summary.entryPoints.isEmpty {
            insights.append(Insight(
                icon: "play.circle.fill",
                title: "\(summary.entryPoints.count) methods available for tracing",
                description: "You can trace execution flows through your code.",
                severity: .info
            ))
        }

        if summary.moduleImports.count >= 2 {
            insights.append(Insight(
                icon: "shippingbox.fill",
                title: "\(summary.moduleImports.count) external modules imported",
                description: "See how your project's modules depend on each other.",
                severity: .info
            ))
        }
    }
}
