import Foundation
import SwiftUMLBridgeFramework

// MARK: - Source read notices

extension DiagramViewModel {
    /// Moves `drained`, by default all of `SourceReadNotices`, into `sourceReadNotices`, keeping
    /// only those about a selected file or a file in a selected folder, once each (#148).
    ///
    /// The framework keeps its notices for the whole process, and a generation a newer one
    /// replaced still runs to its end and records what it finds. Filtering by the selection keeps
    /// a parse of files no longer selected out of the banner.
    func collectSourceReadNotices(_ drained: [String] = SourceReadNotices.drain()) {
        let selected = selectedPaths.map(Self.resolvedPath)
        for notice in drained where !sourceReadNotices.contains(notice) {
            guard let place = SourceReadNoticeBanner.Place(notice: notice) else { continue }
            let file = Self.resolvedPath(place.file)
            if selected.contains(where: { file == $0 || file.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
                sourceReadNotices.append(notice)
            }
        }
    }

    /// `path` with its symlinks resolved, so `/tmp/x` and `/private/tmp/x` compare equal.
    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
