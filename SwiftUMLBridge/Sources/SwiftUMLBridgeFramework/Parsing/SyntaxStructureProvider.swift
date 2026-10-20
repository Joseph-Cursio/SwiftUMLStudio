import Foundation
import SourceKittenFramework
import SwiftSyntax

internal extension SyntaxStructure {

    // MARK: - Public entry points

    /// Parse a Swift source file from disk. Runs a SourceKit typename supplement
    /// whenever a file URL or SDK path is available.
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
    /// (`ModuleReexports`), in a file of its own module or of a module it imports.
    static func declarations(
        inPackageFiles files: [(url: URL, module: String?)], sdkPath: String? = nil
    ) -> [SyntaxStructure] {
        var items: [SyntaxStructure] = []
        var reexports = ModuleReexports()
        for file in files {
            guard let parsed = parsed(file.url, sdkPath: sdkPath, module: file.module) else { continue }
            if let module = file.module { reexports.record(parsed.reexports, from: module) }
            items += parsed.structure?.substructure ?? []
        }
        reexports.widenImports(of: items)
        return items
    }

    private static func parsed(
        _ fileOnDisk: URL, sdkPath: String?, module: String?
    ) -> (structure: SyntaxStructure?, reexports: Set<String>)? {
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

    /// Parse Swift source from an in-memory string. Runs a SourceKit typename
    /// supplement (without SDK) to resolve inferred variable types.
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

    private static func build(
        from source: String,
        sdkPath: String?,
        fileURL: URL?,
        module: String? = nil,
        supplementsTypenames: Bool = true
    ) -> (structure: SyntaxStructure?, reexports: Set<String>) {
        ParsingStack.run {
            // Step 1 — optional SourceKit pass for inferred variable typenames
            let typenameMap = supplementsTypenames
                ? buildTypenameMap(from: source, sdkPath: sdkPath, file: fileURL) : [:]

            // Step 2 — SwiftSyntax primary parse
            let sourceFile = ParsingStack.parse(source, file: fileURL)
            let filePath = fileURL?.path ?? ""
            let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
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
                imports: ImportExtractor.importedModules(in: sourceFile)
            )
            builder.walk(sourceFile)

            return (
                SyntaxStructure(substructure: builder.topLevelItems.isEmpty ? nil : builder.topLevelItems),
                ImportExtractor.reexportedModules(in: sourceFile)
            )
        }
    }

    // MARK: - SourceKit typename supplement

    /// Runs a SourceKit structure pass and returns a map from the UTF-8 offset of each variable's
    /// name to the type SourceKit gives it, for variables whose type cannot be read from the syntax
    /// tree alone (inferred types).
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
        let file = File(contents: NestedSquareBrackets.readable(source, file: fileURL))
        let structure: Structure
        do {
            if let sdk = sdkPath, !sdk.isEmpty {
                guard let docs = SwiftDocs(file: file, arguments: ["-j4", "-sdk", sdk, ""]) else {
                    BridgeLogger.shared.warning("SwiftDocs failed — typename supplement skipped")
                    return [:]
                }
                structure = Structure(sourceKitResponse: docs.docsDictionary)
            } else {
                structure = try Structure(file: file)
            }
        } catch {
            BridgeLogger.shared.warning("SourceKit structure pass failed: \(error)")
            return [:]
        }

        var map: [Int: String] = [:]
        collectTypenames(from: structure.dictionary, into: &map)
        return map
    }

    /// Recursively walks SourceKit's response and collects `nameOffset → typename` entries for
    /// variable declarations that have a resolved type.
    ///
    /// It walks the response as SourceKitten returns it. It used to write `Structure.description`,
    /// pretty-printed JSON, and parse that back, which cost an encode and a decode for every file
    /// and recursed twice more over the response's nesting. Foundation's JSON writer took about
    /// 9.7 KB of stack a nested call, more than SwiftParser in a release build, so in a release
    /// build it was the recursion that overflowed first (#71).
    private static func collectTypenames(
        from dict: [String: SourceKitRepresentable],
        into map: inout [Int: String]
    ) {
        let varKinds: Set<String> = [
            ElementKind.varInstance.rawValue,
            ElementKind.varStatic.rawValue,
            ElementKind.varClass.rawValue
        ]

        let kind = dict["key.kind"] as? String ?? ""
        if varKinds.contains(kind), let offset = dict["key.nameoffset"] as? Int64,
           let typename = dict["key.typename"] as? String {
            map[Int(offset)] = typename.singleLineTypeName
        }

        for key in ["key.substructure", "key.elements"] {
            guard let children = dict[key] as? [SourceKitRepresentable] else { continue }
            for case let child as [String: SourceKitRepresentable] in children {
                collectTypenames(from: child, into: &map)
            }
        }
    }
}
