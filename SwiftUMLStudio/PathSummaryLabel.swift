import SwiftUI

/// The truncating, secondary-styled path summary shown in both toolbars.
struct PathSummaryLabel: View {
    let pathSummary: String

    var body: some View {
        Text(pathSummary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 300, alignment: .leading)
    }
}
