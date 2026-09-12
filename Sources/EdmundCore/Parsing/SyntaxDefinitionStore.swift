import Foundation

// MARK: - Syntax Definition Store
//
// Loads language definitions from two sources — the bundled JSON under
// Resources/Syntaxes and the user's Application Support dir — and resolves a
// fence's info string (or its alias) to a definition. A user def overrides a
// bundled one of the same name, which is what makes a bundled language
// customizable: drop a same-named JSON and it wins.
//
// ponytail: not thread-safe. Tokenization runs during rendering (main thread) and
// the app pushes config / reloads on the main thread, so a plain shared instance
// is enough. Add a lock only if a background tokenizer ever appears.

public final class SyntaxDefinitionStore {
    // ponytail: single-thread (main) use — see the type note above. Matches the
    // codebase's `nonisolated(unsafe)` singleton idiom (Log, image caches).
    nonisolated(unsafe) public static let shared = SyntaxDefinitionStore()

    /// The outcome of resolving a fence's language against the loaded defs.
    enum Resolution: Equatable {
        case plain                              // explicitly no highlighting
        case definition(LanguageDefinition)     // a known language
        case unknown                            // tagged, but no def → C-family fallback
    }

    /// The language a fence with no info string is highlighted as. "plain" = none.
    public var defaultLanguage: String = "plain"

    private var byName: [String: LanguageDefinition] = [:]   // name + aliases → def
    private var ordered: [LanguageDefinition] = []           // dedup by name, for the UI list
    private var userNames: Set<String> = []                  // names sourced from the user dir
    private var sourceURLs: [String: URL] = [:]              // canonical name → backing JSON file

    /// Info-string spellings that mean "no highlighting".
    private static let plainAliases: Set<String> =
        ["", "plain", "plaintext", "text", "none", "txt"]

    init() { reload() }

    // MARK: Loading

    /// Rebuild the tables from bundled + user defs. Call after an import/removal.
    public func reload() {
        var map: [String: LanguageDefinition] = [:]
        var list: [LanguageDefinition] = []
        var users: Set<String> = []
        var sources: [String: URL] = [:]

        func add(_ def: LanguageDefinition, url: URL, user: Bool) {
            if let i = list.firstIndex(where: { $0.name == def.name }) { list[i] = def }
            else { list.append(def) }
            map[def.name] = def
            for a in def.aliases { map[a] = def }
            sources[def.name] = url
            if user { users.insert(def.name) } else { users.remove(def.name) }
        }

        for (def, url) in Self.loadBundled() { add(def, url: url, user: false) }
        for (def, url) in Self.loadUser()    { add(def, url: url, user: true) }  // user overrides bundled

        byName = map
        ordered = list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        userNames = users
        sourceURLs = sources
    }

    // MARK: Resolution

    func resolve(_ language: String?) -> Resolution {
        let key = (language ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if Self.plainAliases.contains(key) { return .plain }
        if let def = byName[key] { return .definition(def) }
        return .unknown
    }

    // MARK: UI queries

    /// `(id, label)` rows for the settings popup / list, "Plain Text" first.
    public func availableLanguages() -> [(id: String, label: String)] {
        [("plain", "Plain Text")] + ordered.map { (id: $0.name, label: $0.label) }
    }

    public func isUserDefinition(_ name: String) -> Bool { userNames.contains(name.lowercased()) }

    /// The JSON file backing a def (user copy if it overrides, else bundled).
    public func fileURL(forName name: String) -> URL? { sourceURLs[name.lowercased()] }

    // MARK: Filesystem

    /// The canonical, update-proof home for user-editable defs:
    /// ~/Library/Application Support/Edmund/Syntaxes. Survives app and macOS
    /// updates (unlike an in-bundle path).
    public static var userDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Edmund/Syntaxes", isDirectory: true)
    }

    /// The bundled `Syntaxes/*.json` files, resolved **without** touching
    /// `Bundle.module` unless it is known to be safe.
    ///
    /// `Bundle.module` is SwiftPM's generated accessor, and on macOS it *traps*
    /// (`fatalError` → EXC_BREAKPOINT / SIGTRAP — not a throwable Swift error)
    /// when the resource bundle it points at isn't a legal `Bundle`. The bundle
    /// `.copy("Resources/Syntaxes")` produces is just a `Syntaxes/` folder; it
    /// only becomes a legal bundle once the packaging step writes an
    /// `Info.plist` into it (see `scripts/build-app.sh`).
    ///
    /// That gap crashed the Quick Look appex: a Space-bar preview in Finder
    /// reached `reload()` → `Bundle.module` on the first md file and trapped
    /// (issue #8). Packaging now writes the missing plist, and this lookup adds
    /// a second line of defence — it finds the JSON files by path first and only
    /// calls `Bundle.module` when that came up empty *and* the bundle it would
    /// use is well-formed. A mis-packaged bundle therefore degrades to "no
    /// syntax highlighting" instead of taking the process down.
    private static func loadBundled() -> [(LanguageDefinition, URL)] {
        syntaxResourceURLs().compactMap(decode)
    }

    private static func syntaxResourceURLs() -> [URL] {
        for directory in bundledSyntaxDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { continue }
            let json = entries.filter { $0.pathExtension.lowercased() == "json" }
            if !json.isEmpty { return json }
        }
        // Nothing found by path. SwiftPM's accessor is the last resort, and only
        // when its bundle is well-formed enough that the accessor's own
        // precondition holds — otherwise it would trap right here.
        if let module = wellFormedModuleBundle {
            return module.urls(forResourcesWithExtension: "json", subdirectory: "Syntaxes") ?? []
        }
        Log.error("No bundled Syntaxes resources found; code blocks render unhighlighted",
                  category: .io)
        return []
    }

    /// Every place the `Syntaxes` payload can live, most specific first:
    /// 1. next to the running binary's resources (`Bundle.main.resourceURL`):
    ///    the app's `Contents/Resources`, an appex's `Contents/Resources` — and,
    ///    for `swift test`, the test bundle's resources next to the JSON itself.
    ///    A flat `Syntaxes/` folder here is what SwiftPM's `.copy` lands as when
    ///    it isn't wrapped in a resource bundle.
    /// 2. inside the module's resource bundle, wherever that bundle is: the
    ///    `.app` root, `Contents/Resources`, or the directory of the test bundle.
    ///    Its payload lives at `Contents/Resources/Syntaxes` once it's a legal
    ///    bundle (see `scripts/build-app.sh`) and at `Syntaxes` while flat.
    ///
    /// The bundle's *name* is deliberately not assumed. SwiftPM derives it from
    /// the package and target (`Edmund_EdmundCore.bundle` here) but the product
    /// name decides what ships — the Quick Look appex is assembled by hand and
    /// has carried `EdmundCore_EdmundCore.bundle`. Looking for one spelling makes
    /// the whole lookup silently fail on the other, which is exactly how a
    /// preview ends up unable to load its syntax defs. Matching any
    /// `*EdmundCore.bundle` directory does not care which one is present.
    ///
    /// Read-only probing: a path that doesn't exist simply yields nothing.
    private static var bundledSyntaxDirectories: [URL] {
        var roots: [URL] = []
        for bundle in [Bundle.main, Bundle(for: SyntaxDefinitionStore.self)] {
            if let resources = bundle.resourceURL { roots.append(resources) }
            roots.append(bundle.bundleURL)
        }
        // Deduplicate: `Bundle.main` and `Bundle(for:)` are the same object under
        // `swift test`, and a repeated root only repeats the same failed lookups.
        var seenRoots = Set<String>()
        var directories: [URL] = []
        for root in roots where seenRoots.insert(root.path).inserted {
            directories.append(root.appendingPathComponent("Syntaxes", isDirectory: true))
            for bundle in moduleResourceBundles(in: root) {
                directories.append(bundle.appendingPathComponent("Contents/Resources/Syntaxes",
                                                                 isDirectory: true))
                directories.append(bundle.appendingPathComponent("Syntaxes", isDirectory: true))
            }
        }
        return directories
    }

    /// Every SwiftPM-style resource bundle for this module that sits directly in
    /// `directory`, whatever it is named. Empty when there is none — a missing
    /// bundle is a normal case (the app also ships the defs flat), not an error.
    private static func moduleResourceBundles(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter {
            $0.pathExtension == "bundle" && $0.lastPathComponent.contains("EdmundCore")
        }
    }

    private static func loadUser() -> [(LanguageDefinition, URL)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: userDirectory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "json" }.compactMap(decode)
    }

    private static func decode(_ url: URL) -> (LanguageDefinition, URL)? {
        guard let data = try? Data(contentsOf: url),
              let def = try? JSONDecoder().decode(LanguageDefinition.self, from: data)
        else { return nil }
        return (def, url)
    }
}
