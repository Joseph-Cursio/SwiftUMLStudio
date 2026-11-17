// swiftlint:disable:next unused_import - memcmp and memchr are Darwin's, which Foundation re-exports
import Foundation

/// The tie-break `DeclarationScope.nearestByDirectory(among:scope:)` takes among candidates equally
/// near a writer of no known module (#233): the first whose target's directory is named for a
/// module the writer's file imports. Swift reads a bare name only in the file's own module and the
/// modules it imports, so of two equally near targets the one it imports is the one that compiles,
/// where the first read was a guess that changed with argument order.
///
/// A directory is only a guess at a module, so the tie-break goes by SwiftPM's layout alone, where
/// a target is the directory right after `Sources`, `Tests` and the like (`moduleDirectory(of:from:
/// afterRoot:)`), and only when each tied candidate's target lies past what it shares with the
/// writer. Then none of them is in the writer's own target, which would be nearer. Otherwise, as
/// for folders of one target, `Sources/ModZ/Foundation` beside the writer's `Sources/ModZ/Views`,
/// or an Xcode project's `Shared/`, which may be compiled into the writer's own target, the first
/// read stands.
extension DeclarationScope {
    /// The first of `candidates` that starts with `prefix` and whose target's directory past it
    /// (`moduleDirectory(of:from:afterRoot:)`) is named for a module this scope's file imports
    /// whole; `nil` when none is, or when the tie is not one this can read. That is when a
    /// candidate so starting has no target past the prefix, or a target a scoped import names,
    /// `import class ModB.Base`, which shadows a whole import for the name it imports, not known
    /// here. It is also when one so named is not seen from other modules, neither `public`,
    /// `open` nor `package`, nor `internal` to a file that imports it with `@testable`: then the
    /// name may well mean the other's. And it is when some targets come right after a `Sources` the writer
    /// shares, others from a deeper one: an Xcode project's folders, `src/Shared` beside the
    /// writer's `src/iOS`, read as targets beside a package's. Neither the `@_spi` entry
    /// (`ImportExtractor.spiImport`) nor an SDK module (`sdkModules`) counts, as a folder named
    /// `UIKit` or `Foundation` under `Source/` is likelier grouping than that module. A name can
    /// have thousands of candidates, tied with each other for writers in thousands of
    /// directories, so it compares bytes, past the prefix alone.
    func importedAmong<Candidate>(
        _ candidates: ArraySlice<Candidate>,
        sharing prefix: UnsafeBufferPointer<UInt8>,
        scope: (Candidate) -> Self
    ) -> Candidate? {
        guard let imports, let writer = WriterImports(imports, leaving: Self.sdkModules) else { return nil }
        let afterRoot = Self.endsInSourceRoot(prefix)
        var chosen: Candidate?
        var shape: TargetShape?
        for candidate in candidates {
            let candidateScope = scope(candidate)
            guard var path = candidateScope.filePath else { continue }
            let tie = path.withUTF8 { bytes in
                Self.tie(
                    of: bytes, past: prefix, afterRoot: afterRoot, imports: writer,
                    access: candidateScope.accessibility
                )
            }
            switch tie {
            case .notTied:
                continue

            case .undecided:
                return nil

            case let .tied(isImported, candidateShape):
                if let shape, shape != candidateShape { return nil }
                shape = candidateShape
                if isImported, chosen == nil { chosen = candidate }
            }
        }
        return chosen
    }

    /// What the candidate at `path`, of `access`, is to `importedAmong(_:sharing:scope:)`, given
    /// the modules the writer imports whole, scoped and with `@testable`.
    private static func tie(
        of path: UnsafeBufferPointer<UInt8>,
        past prefix: UnsafeBufferPointer<UInt8>,
        afterRoot: Bool,
        imports: WriterImports,
        access: ElementAccessibility?
    ) -> ImportTie {
        guard path.count > prefix.count,
              prefix.isEmpty || memcmp(prefix.baseAddress, path.baseAddress, prefix.count) == 0
        else { return .notTied }
        guard let target = moduleDirectory(of: path, from: prefix.count, afterRoot: afterRoot),
              imports.scoped?.contains(target) != true else { return .undecided }
        let isImported = imports.whole.contains(target)
        if isImported, !isSeen(access, testably: imports.testable.contains(target)) { return .undecided }
        let isImmediate = target.baseAddress == path.baseAddress.map { $0 + prefix.count }
        return .tied(isImported: isImported, shape: isImmediate ? .immediate : .deeper)
    }

    /// The directory of `path` past its first `start` bytes right after the last directory
    /// SwiftPM reads targets from (`sourceRoots`), as `ModB` in `Sources/ModB/Models/B.swift`:
    /// the target's, in SwiftPM's layout. `afterRoot` says whether the directory ending at
    /// `start` is one of those. The last counts, so of `~/src/pkg/Sources/ModB`, `ModB`, and the
    /// file's own name is not a directory. `nil` when there is none past `start`.
    static func moduleDirectory(
        of path: UnsafeBufferPointer<UInt8>, from start: Int, afterRoot: Bool
    ) -> UnsafeBufferPointer<UInt8>? {
        guard let base = path.baseAddress else { return nil }
        var segmentStart = start
        var follows = afterRoot
        var target: UnsafeBufferPointer<UInt8>?
        while segmentStart < path.count,
              let found = memchr(base + segmentStart, Int32(slash), path.count - segmentStart) {
            let end = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            if end > segmentStart {
                let segment = UnsafeBufferPointer(rebasing: path[segmentStart..<end])
                if follows { target = segment }
                follows = isSourceRoot(segment)
            }
            segmentStart = end + 1
        }
        return target
    }

    /// Whether the last directory of `prefix`, which ends with `/`, is one SwiftPM reads targets
    /// from.
    private static func endsInSourceRoot(_ prefix: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let end = prefix.lastIndex(where: { $0 != slash }) else { return false }
        let start = prefix[..<end].lastIndex(of: slash).map { $0 + 1 } ?? 0
        return isSourceRoot(UnsafeBufferPointer(rebasing: prefix[start...end]))
    }

    private static func isSourceRoot(_ segment: UnsafeBufferPointer<UInt8>) -> Bool {
        (3...7).contains(segment.count) && sourceRoots.contains { spells($0, segment) }
    }

    /// Whether a file in another module sees a declaration of `access`: when `public`, `open` or
    /// `package`, and imported `testably`, when `internal` too.
    private static func isSeen(_ access: ElementAccessibility?, testably: Bool) -> Bool {
        guard let access else { return false }
        return access >= (testably ? .internal : .package)
    }

    /// What a candidate is to `importedAmong(_:sharing:scope:)`: not tied; tied, in a target the
    /// writer imports whole or not, that comes right after the shared prefix or deeper; or one
    /// that leaves the tie to the first read.
    private enum ImportTie {
        case notTied
        case tied(isImported: Bool, shape: TargetShape)
        case undecided
    }

    /// Where a tied candidate's target comes from: right after the `Sources` the prefix ends in,
    /// or after a deeper one.
    private enum TargetShape { case immediate, deeper }

    /// Modules of Apple's SDKs and the toolchain that files import for themselves, not as a
    /// project's targets, whose names folders of a target often take.
    private static let sdkModules: Set<String> = [
        "AppKit", "AVFoundation", "Cocoa", "Combine", "CoreData", "CoreFoundation", "CoreGraphics",
        "CoreLocation", "Darwin", "Dispatch", "Foundation", "FoundationEssentials", "Glibc", "MapKit",
        "Network", "Observation", "os", "OSLog", "StoreKit", "Swift", "SwiftData", "SwiftUI",
        "Testing", "UIKit", "WatchKit", "WidgetKit", "XCTest",
    ]

    /// The modules a writer's file imports, as `importedAmong(_:sharing:scope:)` reads them:
    /// whole, by a scoped import, and with `@testable`.
    private struct WriterImports {
        let whole: ImportedModules
        let scoped: ImportedModules?
        let testable: ImportedModules

        /// `nil` when `imports` hold no module imported whole but those `leaving` names. A
        /// module's name starts with a letter or `_`, never with the `@` or `=` of an entry that
        /// marks how a file imports (`ImportExtractor.spiImport`, `ImportExtractor.testablePrefix`).
        init?(_ imports: Set<String>, leaving left: Set<String>) {
            let names = imports.filter { $0.first.map { $0 == "_" || $0.isLetter } == true }
            let wholeNames = names.filter { !$0.contains(".") && !left.contains($0) }
            guard !wholeNames.isEmpty else { return nil }
            whole = ImportedModules(names: wholeNames)
            let scopedNames = Set(names.compactMap { entry in entry.firstIndex(of: ".").map { String(entry[..<$0]) } })
            scoped = scopedNames.isEmpty ? nil : ImportedModules(names: scopedNames)
            let prefix = ImportExtractor.testablePrefix
            let testableNames = imports.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
            testable = ImportedModules(names: Set(testableNames))
        }
    }

    /// Modules by name, for `importedAmong(_:sharing:scope:)`.
    struct ImportedModules {
        private let names: Set<String>
        private let bytes: [[UInt8]]
        /// Whether a name has `_`, as every one a directory comes to by `c99Name(of:)` and not
        /// as spelled does: without one, no directory needs it.
        private let hasUnderscore: Bool

        init(names: Set<String>) {
            self.names = names
            bytes = names.map { Array($0.utf8) }
            hasUnderscore = names.contains { $0.contains("_") }
        }

        /// Whether `directory` is named for one of the modules, as spelled or as Swift names a
        /// target so spelled (`ModuleQualifiers.c99Name(of:)`): `my-lib` is `my_lib`.
        func contains(_ directory: UnsafeBufferPointer<UInt8>) -> Bool {
            if bytes.contains(where: { DeclarationScope.spells($0, directory) }) { return true }
            // A path can spell a name decomposed, `Cafe` and U+0301, that a file imports
            // composed; a string compares them canonically.
            let isASCII = directory.allSatisfy { $0 < 0x80 }
            if !isASCII, let spelled = String(bytes: directory, encoding: .utf8), names.contains(spelled) {
                return true
            }
            guard hasUnderscore else { return false }
            let isIdentifier = directory.allSatisfy { byte in
                byte == UInt8(ascii: "_") || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20)
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            }
            guard !isIdentifier || directory.first.map({ (48...57).contains($0) }) == true else { return false }
            guard let spelled = String(bytes: directory, encoding: .utf8) else { return false }
            return names.contains(ModuleQualifiers.c99Name(of: spelled.precomposedStringWithCanonicalMapping))
        }
    }

    /// Whether `segment` is exactly `name`'s bytes.
    private static func spells(_ name: [UInt8], _ segment: UnsafeBufferPointer<UInt8>) -> Bool {
        name.count == segment.count
            && name.withUnsafeBufferPointer { memcmp($0.baseAddress, segment.baseAddress, name.count) == 0 }
    }

    /// The directories SwiftPM looks for targets in by default: `Sources`, `Source`, `src` and
    /// `srcs` for any target, `Tests` for test targets and `Plugins` for plugins.
    private static let sourceRoots: [[UInt8]] = ["Sources", "Source", "src", "srcs", "Tests", "Plugins"]
        .map { Array($0.utf8) }

    private static let slash = UInt8(ascii: "/")
}
