import AppKit
import EdmundMarkdown

// MARK: - VersionHistoryStore (NSFileVersion)
//
// The disk half of the version-history store: `scanFolder` (a plain directory
// walk) lives with the model in `EdmundMarkdown`, and this extension adds the
// `NSFileVersion` queries. The model — `VersionInfo` — is in `EdmundMarkdown`
// too, since the settings UI and the preview both name it; only the AppKit part
// is here.

extension VersionHistoryStore {

    /// Query macOS version history for each URL and flatten to `VersionInfo`.
    public static func gather(urls: [URL]) -> [VersionInfo] {
        var infos: [VersionInfo] = []
        for url in urls {
            guard let versions = NSFileVersion.otherVersionsOfItem(at: url) else { continue }
            for v in versions {
                let vurl = v.url
                let values = try? vurl.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                infos.append(VersionInfo(id: vurl, sourceURL: url,
                                         date: v.modificationDate ?? .distantPast, size: size))
            }
        }
        return infos
    }

    /// Permanently delete the given versions. Returns any errors encountered.
    public static func remove(_ targets: [VersionInfo]) -> [Error] {
        var errors: [Error] = []
        let bySource = Dictionary(grouping: targets, by: \.sourceURL)
        for (source, list) in bySource {
            guard let versions = NSFileVersion.otherVersionsOfItem(at: source) else { continue }
            let wanted = Set(list.map(\.id))
            for v in versions where wanted.contains(v.url) {
                do { try v.remove() } catch { errors.append(error) }
            }
        }
        return errors
    }
}
