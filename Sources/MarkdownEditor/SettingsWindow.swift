import AppKit
import CoreText
import MarkdownEditorCore

class SettingsWindowController: NSWindowController {

    private var fontPopup: NSPopUpButton!
    private var sizeField: NSTextField!
    private var sizeStepper: NSStepper!
    private var previewLabel: NSTextField!

    /// All open editor views get updated when font changes.
    private var fontFamilies: [String] = []

    /// Builds a complete list of font families by scanning system font
    /// directories. `NSFontManager.availableFontFamilies` omits fonts in
    /// `/System/Library/Fonts/Supplemental/` (Athelas, Iowan Old Style, etc.).
    private static func allInstalledFontFamilies() -> [String] {
        var families = Set(NSFontManager.shared.availableFontFamilies)

        let fontDirs = [
            "/System/Library/Fonts",
            "/System/Library/Fonts/Supplemental",
            "/Library/Fonts",
            NSString("~/Library/Fonts").expandingTildeInPath,
        ]
        let fontExtensions: Set<String> = ["ttf", "ttc", "otf", "dfont"]
        let fm = FileManager.default

        for dir in fontDirs {
            guard let enumerator = fm.enumerator(atPath: dir) else { continue }
            while let file = enumerator.nextObject() as? String {
                let ext = (file as NSString).pathExtension.lowercased()
                guard fontExtensions.contains(ext) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
                if let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
                    for d in descs {
                        if let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String {
                            families.insert(family)
                        }
                    }
                }
            }
        }

        return families.sorted()
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
        loadCurrentSettings()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let margin: CGFloat = 20
        let labelWidth: CGFloat = 70
        let rowHeight: CGFloat = 26
        let spacing: CGFloat = 14

        // --- Row 1: Font Family ---
        let fontLabel = NSTextField(labelWithString: "Font:")
        fontLabel.frame = NSRect(x: margin, y: 110, width: labelWidth, height: rowHeight)
        fontLabel.alignment = .right
        contentView.addSubview(fontLabel)

        fontFamilies = Self.allInstalledFontFamilies()

        fontPopup = NSPopUpButton(frame: NSRect(x: margin + labelWidth + 8, y: 110, width: 220, height: rowHeight), pullsDown: false)
        fontPopup.addItems(withTitles: fontFamilies)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        contentView.addSubview(fontPopup)

        // --- Row 2: Font Size ---
        let sizeLabel = NSTextField(labelWithString: "Size:")
        sizeLabel.frame = NSRect(x: margin, y: 110 - rowHeight - spacing, width: labelWidth, height: rowHeight)
        sizeLabel.alignment = .right
        contentView.addSubview(sizeLabel)

        let sizeY = 110 - rowHeight - spacing

        sizeField = NSTextField(frame: NSRect(x: margin + labelWidth + 8, y: sizeY, width: 60, height: rowHeight))
        sizeField.formatter = numberFormatter()
        sizeField.target = self
        sizeField.action = #selector(sizeFieldChanged(_:))
        contentView.addSubview(sizeField)

        sizeStepper = NSStepper(frame: NSRect(x: margin + labelWidth + 8 + 64, y: sizeY, width: 19, height: rowHeight))
        sizeStepper.minValue = 8
        sizeStepper.maxValue = 72
        sizeStepper.increment = 1
        sizeStepper.valueWraps = false
        sizeStepper.target = self
        sizeStepper.action = #selector(stepperChanged(_:))
        contentView.addSubview(sizeStepper)

        // --- Row 3: Preview ---
        let previewY = sizeY - rowHeight - spacing
        previewLabel = NSTextField(labelWithString: "The quick brown fox jumps over the lazy dog.")
        previewLabel.frame = NSRect(x: margin + labelWidth + 8, y: previewY, width: 280, height: rowHeight)
        previewLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(previewLabel)
    }

    private func numberFormatter() -> NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimum = 8
        nf.maximum = 72
        nf.maximumFractionDigits = 0
        return nf
    }

    // MARK: - Load Current Settings

    private func loadCurrentSettings() {
        let name = UserDefaults.standard.string(forKey: "EditorFontName") ?? "Hoefler Text"
        let size = CGFloat(UserDefaults.standard.float(forKey: "EditorFontSize"))
        let resolvedSize = size > 0 ? size : 16

        // Find the font family for the stored font name.
        // The stored name might be a PostScript name — resolve to family.
        let family = fontFamilies.first { fam in
            fam == name || (NSFont(name: name, size: 12)?.familyName == fam)
        } ?? name

        if let idx = fontFamilies.firstIndex(of: family) {
            fontPopup.selectItem(at: idx)
        }
        sizeField.integerValue = Int(resolvedSize)
        sizeStepper.doubleValue = Double(resolvedSize)
        updatePreview()
    }

    // MARK: - Actions

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        applyFont()
    }

    @objc private func sizeFieldChanged(_ sender: NSTextField) {
        let size = max(8, min(72, sender.integerValue))
        sizeStepper.doubleValue = Double(size)
        sizeField.integerValue = size
        applyFont()
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        sizeField.integerValue = Int(sender.doubleValue)
        applyFont()
    }

    // MARK: - Apply

    private func applyFont() {
        guard let family = fontPopup.titleOfSelectedItem else { return }
        let size = CGFloat(sizeField.integerValue)

        // Resolve family name to a usable font name
        let fontName: String
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
           let first = members.first,
           let postscriptName = first[0] as? String {
            fontName = postscriptName
        } else {
            fontName = family
        }

        updatePreview()

        // Update all open editor views
        for document in NSDocumentController.shared.documents {
            if let doc = document as? Document {
                doc.editor?.updateFont(name: fontName, size: size)
            }
        }
    }

    private func updatePreview() {
        guard let family = fontPopup.titleOfSelectedItem else { return }
        let size = CGFloat(sizeField.integerValue)
        if let font = NSFont(name: family, size: size) {
            previewLabel.font = font
        } else if let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let postscriptName = first[0] as? String,
                  let font = NSFont(name: postscriptName, size: size) {
            previewLabel.font = font
        }
    }
}
