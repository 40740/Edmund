import Foundation
import EdmundMarkdown
import EdmundRender

// MARK: - Log (editor-side helpers)
//
// The logger itself lives in `EdmundRender/Diagnostics/Log.swift`, so the Quick
// Look preview — which links the render pipeline and not the editor — writes to
// the same `~/.edmund/logs/edmund-<date>.log` the app does. What stays here is
// the part that needs the editor's block model.

extension Log {

    /// Logs the structure of a block array at `debug` level: each block's kind
    /// and character count, with no document text. Example output:
    ///   Structure (4): heading(2)·18c, paragraph·234c, codeBlock(swift)·456c, callout·120c
    public static func blockStructure(_ blocks: [Block], category: Category = .compose) {
        guard Log.isLoggingEnabled(for: .debug) else { return }
        let parts = blocks.map { b -> String in
            let c = b.range.length
            switch b.kind {
            case .paragraph:              return "paragraph·\(c)c"
            case .heading(let level):     return "heading(\(level))·\(c)c"
            case .quoteRun(let isCallout): return "\(isCallout ? "callout" : "quote")·\(c)c"
            case .fence:                  return "fence·\(c)c"
            case .indentedCode:           return "indentedCode·\(c)c"
            case .mathDisplay:            return "math·\(c)c"
            case .table:                  return "table·\(c)c"
            case .listItem:               return "listItem·\(c)c"
            case .thematicBreak:          return "hr·\(c)c"
            case .htmlBlock:              return "htmlBlock·\(c)c"
            case .blank:                  return "blank·\(c)c"
            case .frontMatter:            return "frontMatter·\(c)c"
            case .multiBlockComment:      return "comment·\(c)c"
            }
        }
        Log.write(level: .debug, category: category,
                  message: "Structure (\(blocks.count)): \(parts.joined(separator: ", "))")
    }
}
