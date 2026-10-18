import Foundation

/// Collect file paths based on a set of constraints
public struct FileCollector: Sendable {
    /// default initializer
    public init() {}

    /// get file urls for given constraints
    /// - Parameters:
    ///   - paths: array of file paths or just use `["."]`
    ///   - directory: root of recursive search
    ///   - fileOptions: containing include/exclude information via Globs
    /// - Returns: an array of URLs, in the order they were found
    public func getFiles(for paths: [String], in directory: String, honoring fileOptions: FileOptions?) -> [URL] {
        let include = fileOptions?.include ?? []
        let exclude = fileOptions?.exclude ?? []

        // Include globs choose the files themselves, so search the whole directory.
        let allFiles = getFiles(for: include.isEmpty ? paths : ["."], in: directory)

        guard let fileOptions, fileOptions.someProvided else {
            return allFiles
        }
        BridgeLogger.shared.info("paths will be ignored in favor of configuration  \(fileOptions.description)")

        let included = expandGlobs(include.joined(separator: ","), in: directory)
        let excluded = expandGlobs(exclude.joined(separator: ","), in: directory)

        // One pass over `allFiles`, so a file comes back at most once and in
        // the order it was found: dropped if any exclude glob matches it and,
        // when there are include globs, kept only if one of them does.
        // The globs are anchored where enumeration reports files, so test each
        // file in that form too: an explicit file argument keeps the spelling
        // it was given, which may run through a symlink.
        return allFiles.filter { url in
            let path = enumeratedPath(of: url)
            if excluded.contains(where: { $0.matches(path) }) {
                return false
            }
            return include.isEmpty || included.contains { $0.matches(path) }
        }
    }

    func getFiles(for paths: [String], in directory: String = FileManager.default.currentDirectoryPath) -> [URL] {
        var sanitizedPaths: [URL?] = []

        if paths.isEmpty {
            sanitizedPaths.append(URL(fileURLWithPath: directory))
        } else if paths.count == 1, paths[0] == "." {
            sanitizedPaths.append(URL(fileURLWithPath: directory))
        } else {
            sanitizedPaths.append(contentsOf: paths.map { path -> URL in
                if path.hasPrefix("/") {
                    return URL(fileURLWithPath: path)
                } else {
                    return URL(fileURLWithPath: directory).appendingPathComponent(path)
                }
            })
        }

        var files: [URL] = []
        for paths in sanitizedPaths.compactMap({ $0 }) {
            files.append(contentsOf: getFiles(for: paths))
        }

        return files
    }

    func getFiles(for url: URL) -> [URL] {
        // A search directory can itself be a symlink. Its resource values
        // describe the link, not the directory, and an enumerator started at
        // the link yields nothing, so walk the directory it resolves to. Files
        // come back under that real path, as they already do for a directory
        // with a symlinked parent.
        let directory = URL(fileURLWithPath: canonicalPath(url.path))
        let isDirectory = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            var files = [URL]()
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            if let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: options
            ) {
                for case let fileURL as URL in enumerator {
                    do {
                        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .typeIdentifierKey]
                        let fileAttributes = try fileURL.resourceValues(forKeys: resourceKeys)
                        let isSwift = fileAttributes.typeIdentifier == "public.swift-source"
                        if fileAttributes.isRegularFile == true, isSwift {
                            files.append(fileURL)
                        }
                    } catch {
                        // Not `print`: the CLI writes the diagram to stdout, and this would land in it.
                        BridgeLogger.shared.warning("skipped \(fileURL.path): \(error.localizedDescription)")
                    }
                }
            }
            return files
        } else {
            return [url]
        }
    }
}

fileprivate extension FileOptions {
    var someProvided: Bool {
        include?.isEmpty == false || exclude?.isEmpty == false
    }
}
