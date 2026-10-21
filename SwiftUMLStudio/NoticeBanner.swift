import SwiftUI

/// The orange strip a notice above the diagram is drawn in: an icon, the notice's text, and a
/// rule along its bottom edge. VoiceOver reads it as one element.
struct NoticeBanner<Content: View>: View {
    let systemImage: String
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .font(.title3)
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.3)), alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
