import Foundation
import SwiftUMLBridgeFramework

// MARK: - Source read notices

extension DiagramViewModel {
    /// Moves `collected`, the notices a generation's own parses found, into `sourceReadNotices`,
    /// keeping only those about a selected file or a file in a selected folder, once each (#148).
    ///
    /// `generate()` collects them per run (`SourceReadNotices.collector`), so neither a run it
    /// replaced (#236) nor one in another window adds to them, or takes them. The selection filter
    /// stays as a guard against a run that read past the selection.
    func collectSourceReadNotices(_ collected: [String]) {
        let selected = selectedPaths.map(Self.resolvedPath)
        for notice in collected where !sourceReadNotices.contains(notice) {
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
