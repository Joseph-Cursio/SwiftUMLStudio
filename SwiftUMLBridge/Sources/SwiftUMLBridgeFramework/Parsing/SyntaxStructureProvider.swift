import Foundation
import SourceKittenFramework
import SwiftSyntax

internal extension SyntaxStructure {

    // MARK: - Public entry points

    /// Parse a Swift source file from disk. Runs a SourceKit typename supplement, which reads
    /// the types written in the source and, given `sdkPath`, the types Swift infers.
    static func create(
        from fileOnDisk: URL,
        sdkPath: String? = nil,
        module: String? = nil
    ) -> SyntaxStructure? {
        parsed(fileOnDisk, sdkPath: sdkPath, module: module)?.structure
    }

    /// The declarations of a package's `files`, each parsed under its module as
    /// `create(from:sdkPath:module:)` parses it, in the order given, with each declaration's
    /// `imports` widened to every module its file sees through an `@_exported import`
    /// (`ModuleReexports`), in a file of its own module or of a module it imports, and its
    /// `loadedModules` read from every file's imports, those of a file that declares nothing too.
    static func declarations(
        inPackageFiles files: [(url: URL, module: String?)], sdkPath: String? = nil
    ) -> [SyntaxStructure] {
        var items: [SyntaxStructure] = []
        var reexports = ModuleReexports()
        var importsForModule: [String: Set<String>] = [:]
        for file in files {
            guard let parsed = parsed(file.url, sdkPath: sdkPath, module: file.module) else { continue }
            if let module = file.module {
                reexports.record(parsed.reexports, from: module)
                importsForModule[module, default: []].formUnion(parsed.imports)
            }
            items += parsed.structure?.substructure ?? []
        }
        reexports.widenImports(of: items)
        let loads = ModuleLoads(importsForModule: importsForModule)
        func stamp(_ item: SyntaxStructure) {
            if let module = item.module { item.loadedModules = loads.loaded(by: module) }
            item.substructure?.forEach(stamp)
        }
        items.forEach(stamp)
        return items
    }

    private static func parsed(_ fileOnDisk: URL, sdkPath: String?, module: String?) -> ParsedFile? {
        let methodStart = ContinuousClock.now
        guard let source = try? String(contentsOf: fileOnDisk, encoding: .utf8) else {
            BridgeLogger.shared.error("not able to read contents of file \(fileOnDisk)")
            return nil
        }
        let parsed = build(from: source, sdkPath: sdkPath, fileURL: fileOnDisk, module: module)
        let elapsed = (ContinuousClock.now - methodStart).seconds
        let sdkLabel = (sdkPath != nil && !sdkPath!.isEmpty) ? "parsing with SDK" : ""
        BridgeLogger.shared.debug("read \(fileOnDisk) \(sdkLabel) in \(elapsed)")
        return parsed
    }

    /// Parse Swift source from an in-memory string. Runs a SourceKit typename supplement
    /// without an SDK or a file, so it reads only the types written in the source.
    static func create(from contents: String, module: String? = nil) -> SyntaxStructure? {
        build(from: contents, sdkPath: nil, fileURL: nil, module: module).structure
    }

    /// Parse `source`, read from `file`, with SwiftSyntax alone: declarations, names and source
    /// locations, but no inferred variable types, which only the SourceKit pass supplies. For
    /// passes that need the declarations and none of the members' types.
    static func declarations(in source: String, file: URL) -> SyntaxStructure? {
        build(from: source, sdkPath: nil, fileURL: file, supplementsTypenames: false).structure
    }

    // MARK: - Core build pipeline

    /// A parsed file: its declarations, and the modules it imports and re-exports, as
    /// `ImportExtractor.importedModules(in:)` and `ImportExtractor.reexportedModules(in:)` read them.
    struct ParsedFile {
        let structure: SyntaxStructure?
        let imports: Set<String>
        let reexports: Set<String>
    }

    private static func build(
        from source: String,
        sdkPath: String?,
        fileURL: URL?,
        module: String? = nil,
        supplementsTypenames: Bool = true
    ) -> ParsedFile {
        ParsingStack.run {
            // Step 1 — optional SourceKit pass for inferred variable typenames
            let typenameMap = supplementsTypenames
                ? buildTypenameMap(from: source, sdkPath: sdkPath, file: fileURL) : [:]

            // Step 2 — SwiftSyntax primary parse
            let sourceFile = ParsingStack.parse(source, file: fileURL)
            let filePath = fileURL?.path ?? ""
            let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
            let imports = ImportExtractor.importedModules(in: sourceFile)
            // A `SyntaxVisitor`, and SwiftSyntax's contract makes it single-use: construct, walk,
            // read the result, discard. A fresh one is needed per parse, so there is no instance to
            // inject and nothing a caller could hold. The six sibling walkers in this codebase that
            // are declared `private` are exempt for exactly this reason; this one lives in its own
            // file, one directory over from its only caller, so the access level cannot say it.
            // swiftprojectlint:disable:next direct-instantiation
            let builder = SyntaxStructureBuilder(
                viewMode: .sourceAccurate,
                typenameMap: typenameMap,
                filePath: filePath,
                locationConverter: converter,
                module: module,
                imports: imports
            )
            builder.walk(sourceFile)

            return ParsedFile(
                structure: SyntaxStructure(substructure: builder.topLevelItems.isEmpty ? nil : builder.topLevelItems),
                imports: imports,
                reexports: ImportExtractor.reexportedModules(in: sourceFile)
            )
        }
    }

    // MARK: - SourceKit typename supplement

    /// Runs a SourceKit structure pass and returns a map from the UTF-8 offset of each variable's
    /// name to the type SourceKit gives it, for variables whose type cannot be read from the syntax
    /// tree alone (inferred types).
    ///
    /// The structure pass (`editor.open`) is syntactic: it knows only the types written in the
    /// source. With an SDK and a file on disk, each variable it leaves untyped also gets a
    /// cursor-info request, which typechecks the file and returns the type Swift infers (#147).
    /// Cursor info needs the file's path, as the request's source file and as the compiler's input
    /// file, and the SDK, to load the standard library. Without both, only written types are known.
    ///
    /// The key is where the name is, not what it is called. A key built from the names of the
    /// enclosing types left extensions out, kept no backticks, and gave the same key to a type
    /// nested in a function, to both clauses of an `#if` and to a type nested in an extension and
    /// a top-level one, so a variable could take another's type (#146). SourceKit's
    /// `key.nameoffset` and SwiftSyntax's `utf8Offset` both count UTF-8 bytes from the start of
    /// the file, so they agree past a byte-order mark and multi-byte text.
    ///
    /// SourceKit's parser doubles its time with each `[` in a chain as SwiftParser does, so it is
    /// given the source SwiftParser is, with the same bytes, and so the same offsets (#148).
    static func buildTypenameMap(from source: String, sdkPath: String?, file fileURL: URL? = nil) -> [Int: String] {
        if BridgeConfiguration.skipSourceKitTypenameSupplement {
            return [:]
        }
        let readable = NestedSquareBrackets.readable(source, file: fileURL)
        let structure: Structure
        do {
            structure = try Structure(file: File(contents: readable))
        } catch {
            BridgeLogger.shared.warning("SourceKit structure pass failed: \(error)")
            return [:]
        }

        var map: [Int: String] = [:]
        var untyped: [Int] = []
        collectTypenames(from: structure.dictionary, into: &map, untyped: &untyped)

        // Cursor info typechecks the file as it is on disk, so a file whose deep `[` chains were
        // blanked out for the parsers is left to the structure pass: typechecking it would take
        // the time the blanking saves.
        guard let sdk = sdkPath, !sdk.isEmpty, let path = fileURL?.path, !untyped.isEmpty,
              readable == source else { return map }
        let byteOrderMark = byteOrderMarkLength(of: path, source: source)
        for offset in untyped {
            if let typename = inferredTypename(at: offset + byteOrderMark, in: path, sdk: sdk) {
                map[offset] = typename.singleLineTypeName
            }
        }
        return map
    }

    /// The type SourceKit's cursor info gives the declaration whose name is at UTF-8 `offset` of
    /// the file at `path`, typechecked alone against `sdk`, or nil where it has none. A type from
    /// another file is unknown to a file typechecked alone, and comes back as `_` or an error
    /// type, so it is left out rather than drawn.
    private static func inferredTypename(at offset: Int, in path: String, sdk: String) -> String? {
        // Unless told not to, SourceKit cancels a cursor-info request when another one arrives,
        // so two files parsed at once (as Swift Testing's parallel tests do) lose their types.
        let request: SourceKitObject = [
            "key.request": UID("source.request.cursorinfo"),
            "key.name": path,
            "key.sourcefile": path,
            "key.offset": Int64(offset),
            "key.compilerargs": ["-sdk", sdk, path],
            "key.cancel_on_subsequent_request": Int64(0)
        ]
        guard let response = try? Request.customRequest(request: request).send(),
              let typename = response["key.typename"] as? String,
              !typename.isEmpty, typename != "_", !typename.contains("<<error type>>") else { return nil }
        return typename
    }

    /// The 3 bytes of a UTF-8 byte-order mark that the file at `path` starts with and `source`,
    /// read from it, does not, or 0. Reading a file into a `String` drops the mark, so the
    /// offsets SourceKit and SwiftSyntax give `source` are 3 short of the file's, which cursor
    /// info reads from disk.
    private static func byteOrderMarkLength(of path: String, source: String) -> Int {
        let mark: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard !source.utf8.starts(with: mark),
              let handle = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: mark.count)) ?? Data()
        return Array(head) == mark ? mark.count : 0
    }

    /// Recursively walks SourceKit's response and collects `nameOffset → typename` entries for
    /// variable declarations that have a type written, and the name offsets of those that have
    /// none in `untyped`.
    ///
    /// It walks the response as SourceKitten returns it. It used to write `Structure.description`,
    /// pretty-printed JSON, and parse that back, which cost an encode and a decode for every file
    /// and recursed twice more over the response's nesting. Foundation's JSON writer took about
    /// 9.7 KB of stack a nested call, more than SwiftParser in a release build, so in a release
    /// build it was the recursion that overflowed first (#71).
    private static func collectTypenames(
        from dict: [String: SourceKitRepresentable],
        into map: inout [Int: String],
        untyped: inout [Int]
    ) {
        let varKinds: Set<String> = [
            ElementKind.varInstance.rawValue,
            ElementKind.varStatic.rawValue,
            ElementKind.varClass.rawValue
        ]

        let kind = dict["key.kind"] as? String ?? ""
        if varKinds.contains(kind), let offset = dict["key.nameoffset"] as? Int64 {
            if let typename = dict["key.typename"] as? String {
                map[Int(offset)] = typename.singleLineTypeName
            } else {
                untyped.append(Int(offset))
            }
        }

        for key in ["key.substructure", "key.elements"] {
            guard let children = dict[key] as? [SourceKitRepresentable] else { continue }
            for case let child as [String: SourceKitRepresentable] in children {
                collectTypenames(from: child, into: &map, untyped: &untyped)
            }
        }
    }
}
