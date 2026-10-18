import SwiftUI

/// Shown above the diagram when a selected file had `[` nested too deep for the parsers to read in
/// time, so they were read as spaces (#148). The diagram is still drawn, and only a type written
/// that deep looks different, so without this nothing said the file was not read as written.
struct SourceReadNoticeBanner: View {
    /// Where each notice points, in the order the parsers found them.
    let places: [Place]

    /// The file, line and column a `SourceReadNotices` notice starts with,
    /// `<file>:<line>:<column>: <what was done>`.
    struct Place: Hashable {
        let file: String
        let line: Int
        let column: Int

        /// `nil` for a notice that does not start with a file, line and column.
        init?(notice: String) {
            guard let match = notice.prefixMatch(of: #/(?<file>.+):(?<line>\d+):(?<column>\d+): /#),
                  let line = Int(match.line), let column = Int(match.column) else { return nil }
            self.file = String(match.file)
            self.line = line
            self.column = column
        }

        /// `Grid.swift, line 2, column 25`.
        var label: String {
            "\(URL(fileURLWithPath: file).lastPathComponent), line \(line), column \(column)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.badge.xmark")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headline).font(.subheadline.bold())
                Text(Self.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(places, id: \.self) { place in
                    Text(place.label)
                        .font(.caption.monospaced())
                        .help(place.file)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.orange.opacity(0.3)), alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sourceReadNoticeBanner")
    }

    static let headline = "Deeply nested brackets read as spaces"

    static let detail = "Each [ nested past the parser's limit in other [, and the ] that closes it, "
        + "was read as a space, as each one doubles the time a parse takes. The rest of the file "
        + "was read, and only a type written that deep looks different."

    /// The places to show for `notices`, or `nil` when the banner should stay hidden: while a
    /// diagram is generating, and when no notice names a place.
    static func places(for notices: [String], isGenerating: Bool) -> [Place]? {
        guard !isGenerating else { return nil }
        let places = notices.compactMap(Place.init(notice:))
        return places.isEmpty ? nil : places
    }
}
