import SwiftUI

struct ArchitectureDiffView: View {
    let diff: ArchitectureDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Changes since \(diff.previousTimestamp, style: .relative) ago")
                    .font(.headline)
                Spacer()
            }

            summaryRow

            if !diff.typeBreakdownDeltas.isEmpty {
                breakdownSection
            }

            if !diff.complexityChanges.isEmpty {
                complexitySection
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 16) {
            DeltaChip(label: "Types", delta: diff.typeDelta)
            DeltaChip(label: "Relationships", delta: diff.relationshipDelta)
            DeltaChip(label: "Modules", delta: diff.moduleDelta)
            DeltaChip(label: "Files", delta: diff.fileDelta)
        }
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type Breakdown Changes")
                .font(.subheadline.bold())
            ForEach(diff.typeBreakdownDeltas.sorted(by: { abs($0.value) > abs($1.value) }), id: \.key) { kind, delta in
                HStack {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DeltaLabel(delta: delta)
                }
            }
        }
    }

    // MARK: - Complexity

    private var complexitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Complexity Changes")
                .font(.subheadline.bold())
            ForEach(diff.complexityChanges.prefix(5), id: \.name) { change in
                HStack {
                    Text(change.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    DeltaLabel(delta: change.delta)
                    Text(change.delta > 0 ? "more connections" : "fewer connections")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct DeltaChip: View {
    let label: String
    let delta: Int

    var body: some View {
        VStack(spacing: 2) {
            DeltaLabel(delta: delta)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var chipBackground: some ShapeStyle {
        if delta > 0 {
            return AnyShapeStyle(.green.opacity(0.1))
        } else if delta < 0 {
            return AnyShapeStyle(.red.opacity(0.1))
        } else {
            return AnyShapeStyle(.quaternary.opacity(0.3))
        }
    }
}

struct DeltaLabel: View {
    let delta: Int

    var body: some View {
        Text(deltaText)
            .font(.body.bold().monospacedDigit())
            .foregroundStyle(deltaColor)
    }

    private var deltaText: String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "0"
    }

    private var deltaColor: Color {
        if delta > 0 { return .green }
        if delta < 0 { return .red }
        return .secondary
    }
}
