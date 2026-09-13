import AppKit

// MARK: - ImageLoadFailure
//
// Why an `![alt](destination)` couldn't be shown — the short label a
// blocked-image placeholder draws next to its icon. Shared by Edit mode (the
// editor draws the placeholder itself) and Read mode/export (the HTML renderer
// emits it) so the two report the same reason, in the same words, for the same
// failure, which is why it lives with the HTML pipeline rather than with either
// back-end.

/// Why an `![alt](destination)` couldn't be shown — the short label a
/// blocked-image placeholder draws next to its icon. Shared by Edit mode
/// (this file) and Read mode/export (`DocumentHTML`) so the two report the
/// same reason, in the same words, for the same failure.
public enum ImageLoadFailure: Equatable {
    case httpUnsupported
    case blockedBySetting
    case notAnImage
    case notFound
    /// The file is there, but this process isn't allowed to read it — sandbox
    /// denial or POSIX permissions. Distinct from `.notFound` because the fix is
    /// different (run the app, or move the file), and "Image not found" would send
    /// the reader looking for a file that is sitting right there.
    case notReadable
    /// A `![[file]]` embed of a type Obsidian supports (audio/video/pdf/note)
    /// but Edmund can't render.
    case embedTypeUnsupported
    /// A `![[file]]` embed of a type Obsidian itself doesn't support either.
    case embedTypeGenerallyUnsupported

    public var label: String {
        switch self {
        case .httpUnsupported: return "HTTP connection not supported"
        case .blockedBySetting: return "External images blocked"
        case .notAnImage: return "Not an image"
        case .notFound: return "Image not found"
        case .notReadable: return "No permission to read image"
        case .embedTypeUnsupported: return "Embeded file not an image"
        case .embedTypeGenerallyUnsupported: return "Embed file type generally unsupported"
        }
    }

    /// Classifies a non-image `![[file]]` embed by its extension. Obsidian
    /// supports audio/video/pdf/note embeds but Edmund can't render them
    /// (`.embedTypeUnsupported`); anything else Obsidian wouldn't embed either
    /// (`.embedTypeGenerallyUnsupported`). Shared by Edit and Read so the two
    /// report the same reason. No extension ⇒ a note embed (`.md` implied).
    public static func forEmbed(destination: String) -> ImageLoadFailure {
        let ext = (destination as NSString).pathExtension.lowercased()
        let obsidianSupported: Set<String> = [
            "mp3", "wav", "m4a", "ogg", "3gp", "flac",   // audio
            "mp4", "webm", "ogv", "mov", "mkv",          // video
            "pdf", "md",                                 // pdf + embedded note
        ]
        return ext.isEmpty || obsidianSupported.contains(ext)
            ? .embedTypeUnsupported : .embedTypeGenerallyUnsupported
    }
}
