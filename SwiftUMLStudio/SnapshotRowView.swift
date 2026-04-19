import SwiftUI

struct SnapshotRowView: View {
    let snapshot: ProjectSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
                Text(formattedDate)
                    .font(.caption.bold())
            }
            HStack(spacing: 8) {
                Label("\(snapshot.typeCount) types", systemImage: "rectangle.3.group")
                Label("\(snapshot.relationshipCount) rels", systemImage: "arrow.triangle.branch")
                Label("\(snapshot.moduleCount) mods", systemImage: "shippingbox")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        guard let date = snapshot.timestamp else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
