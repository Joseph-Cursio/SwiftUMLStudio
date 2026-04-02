import Foundation
import SourceKittenFramework
import SwiftParser
import SwiftSyntax

internal extension SyntaxStructure {

    // MARK: - Public entry points

    /// Parse a Swift source file from disk. Runs a SourceKit typename supplement
    /// whenever a file URL or SDK path is available.
    static func create(from fileOnDisk: URL, sdkPath: String? = nil) -> SyntaxStructure? {
        let methodStart = Date()
        guard let source = try? String(contentsOf: fileOnDisk, encoding: .utf8) else {
            BridgeLogger.shared.error("not able to read contents of file \(fileOnDisk)")
            return nil
        }
        let structure = build(from: source, sdkPath: sdkPath, fileURL: fileOnDisk)
        let elapsed = Date().timeIntervalSince(methodStart)
        let sdkLabel = (sdkPath != nil && !sdkPath!.isEmpty) ? "parsing with SDK" : ""
        BridgeLogger.shared.debug("read \(fileOnDisk) \(sdkLabel) in \(elapsed)")
        return structure
    }

    /// Parse Swift source from an in-memory string. Runs a SourceKit typename
    /// supplement (without SDK) to resolve inferred variable types.
    static func create(from contents: String) -> SyntaxStructure? {
        build(from: contents, sdkPath: nil, fileURL: nil)
    }

    // MARK: - Core build pipeline

    private static func build(
        from source: String,
        sdkPath: String?,
        fileURL: URL?
    ) -> SyntaxStructure? {
        // Step 1 — optional SourceKit pass for inferred variable typenames
        let typenameMap = buildTypenameMap(from: source, sdkPath: sdkPath)

        // Step 2 — SwiftSyntax primary parse
        let sourceFile = Parser.parse(source: source)
        let builder = SyntaxStructureBuilder(viewMode: .sourceAccurate, typenameMap: typenameMap)
        builder.walk(sourceFile)

        return SyntaxStructure(substructure: builder.topLevelItems.isEmpty ? nil : builder.topLevelItems)
    }

    // MARK: - SourceKit typename supplement

    /// Runs a SourceKit structure pass and returns a map of
    /// `"TypeName.varName" → resolvedTypeName` for variables whose type cannot
    /// be read from the syntax tree alone (inferred types).
    private static func buildTypenameMap(from source: String, sdkPath: String?) -> [String: String] {
        let file = File(contents: source)
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

        guard let jsonData = structure.description.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            BridgeLogger.shared.error("Failed to parse SourceKit JSON for typename supplement")
            return [:]
        }

        var map: [String: String] = [:]
        collectTypenames(from: root, typeContext: [], into: &map)
        return map
    }

    /// Recursively walks a SourceKit JSON dictionary and collects
    /// `qualifiedName → typename` entries for variable declarations that have a
    /// resolved type.
    private static func collectTypenames(
        from dict: [String: Any],
        typeContext: [String],
        into map: inout [String: String]
    ) {
        let typeKinds: Set<String> = [
            ElementKind.class.rawValue,
            ElementKind.struct.rawValue,
            ElementKind.enum.rawValue,
            ElementKind.protocol.rawValue,
            ElementKind.actor.rawValue,
            // SourceKit reports actors as class on macOS 26 — include both
            "source.lang.swift.decl.class"
        ]
        let varKinds: Set<String> = [
            ElementKind.varInstance.rawValue,
            ElementKind.varStatic.rawValue,
            ElementKind.varClass.rawValue
        ]

        let kind = dict["key.kind"] as? String ?? ""
        let name = dict["key.name"] as? String ?? ""

        if varKinds.contains(kind), !name.isEmpty, let typename = dict["key.typename"] as? String {
            let qualified = (typeContext + [name]).joined(separator: ".")
            map[qualified] = typename
        }

        var nextContext = typeContext
        if typeKinds.contains(kind), !name.isEmpty {
            nextContext = typeContext + [name]
        }

        for key in ["key.substructure", "key.elements"] {
            if let children = dict[key] as? [[String: Any]] {
                for child in children {
                    collectTypenames(from: child, typeContext: nextContext, into: &map)
                }
            }
        }
    }
}
