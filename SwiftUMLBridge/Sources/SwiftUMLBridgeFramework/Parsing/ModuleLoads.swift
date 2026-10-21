/// The modules each module of a class diagram loads: every module a file of it imports, all of
/// it or a declaration of it, and in turn every module those load. Without
/// `MemberImportVisibility`, Swift shows the members an extension adds in every file of a module
/// that loads the extension's module, whichever file imports it, so `Foo.V` there can mean a `V`
/// that ModB adds to ModA's `Foo` though the file that writes it imports only ModA
/// (`TypeLookup.isLoaded(_:from:depth:)`). Modules are matched by the name Swift code writes for
/// them (`ModuleQualifiers.c99Name(of:)`), as imports name them, and each set also holds the
/// target names of the modules it has, so a declaration's `module` is looked up as it is.
struct ModuleLoads {
    private var loadedForModule: [String: Set<String>] = [:]
    /// The modules whose loads count every file of them (`knowsEveryLoad(of:)`).
    private var modulesReadWhole: Set<String> = []

    /// The loads of the modules whose files import `importsForModule`, as
    /// `ImportExtractor.importedModules(in:)` reads them: a scoped import loads its whole module.
    init(importsForModule: [String: Set<String>]) {
        var imported: [String: Set<String>] = [:]
        var targetsForName: [String: Set<String>] = [:]
        for (module, imports) in importsForModule {
            let name = ModuleQualifiers.c99Name(of: module)
            targetsForName[name, default: []].insert(module)
            imported[name, default: []].formUnion(
                imports.map { ModuleQualifiers.c99Name(of: String($0.prefix { $0 != "." })) }
            )
        }
        for name in imported.keys {
            var loaded: Set<String> = [name]
            var pending = [name]
            while let next = pending.popLast() {
                for dependency in imported[next] ?? [] where loaded.insert(dependency).inserted {
                    pending.append(dependency)
                }
            }
            let withTargets = loaded.union(loaded.flatMap { targetsForName[$0] ?? [] })
            loadedForModule[name] = withTargets
            for target in targetsForName[name] ?? [] { loadedForModule[target] = withTargets }
        }
    }

    /// The loads of the modules of `items`, from each one's `SyntaxStructure.loadedModules`, which
    /// counts every file of a package, or else from the imports of the files that declare them.
    init(of items: [SyntaxStructure] = []) {
        var importsForModule: [String: Set<String>] = [:]
        // Every item of a module carries the same `loadedModules`, so they are read once.
        var readWhole: Set<String> = []
        func gather(_ item: SyntaxStructure) {
            defer { item.mergedExtensions.forEach(gather) }
            guard let module = item.module, !readWhole.contains(module),
                  let imports = item.loadedModules ?? item.imports else { return }
            if item.loadedModules != nil { readWhole.insert(module) }
            importsForModule[module, default: []].formUnion(imports)
        }
        items.forEach(gather)
        self.init(importsForModule: importsForModule)
        modulesReadWhole = readWhole
    }

    /// `module` and every module it loads.
    func loaded(by module: String) -> Set<String> {
        if let loaded = loadedForModule[module] { return loaded }
        let name = ModuleQualifiers.c99Name(of: module)
        return loadedForModule[name] ?? [module, name]
    }

    /// Whether `module`'s loads were read from `SyntaxStructure.loadedModules`, which counts every
    /// file of it, so a module it does not load surely shows none of that module's members.
    func knowsEveryLoad(of module: String) -> Bool {
        modulesReadWhole.contains(module)
    }

    /// Whether a file of `writer` sees the members that an extension in `module` adds.
    func loads(_ module: String, in writer: String) -> Bool {
        module == writer || loaded(by: writer).contains(module)
    }
}
