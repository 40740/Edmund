// The Key Bindings settings pane: menu list on the left, that menu's commands
// and their shortcuts on the right. Only Edmund's own commands appear — the
// OS-standard items (New, Save, Cut/Copy/Paste, Undo, Quit, Minimize) are not
// rebindable, so they are not listed.
//
// Editing is CotEditor's model: click the key cell, type the chord. A chord
// already in use anywhere in the menu bar is refused with a beep and an
// explanation, and the cell keeps recording so the user can try another.

import SwiftUI
import AppKit

struct KeyBindingsSettingsView: View {
    @State private var selectedGroup: String?
    @State private var error: String?
    /// Bumped after every accepted edit to re-read shortcuts out of the store.
    @State private var revision = 0

    private static let menuColumnWidth: CGFloat = 150
    private static let keyColumnWidth: CGFloat = 90

    private var groups: [String] { KeyBindingCatalog.shared.groups }

    private var rows: [KeyBindingCatalog.Entry] {
        KeyBindingCatalog.shared.entries(inGroup: selectedGroup ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To change a shortcut, click the key column, then type the new keys.")

            // A hand-built header over two plain Lists rather than SwiftUI
            // `Table`s: Table draws a separator under every row, which this pane
            // (like CotEditor's) doesn't want, and there's no modifier to turn
            // them off.
            VStack(spacing: 0) {
                header
                Divider()
                lists
            }
            .border(Color(nsColor: .separatorColor))
            .frame(height: 300)
            .onAppear { if selectedGroup == nil { selectedGroup = groups.first } }

            HStack {
                Button("Restore Defaults", action: restoreDefaults)
                    .disabled(!KeyBindingStore.hasAnyOverride)
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        // Every settings pane is 600 wide, so switching tabs only ever resizes
        // the window vertically.
        .frame(width: 600)
    }

    /// The column titles, laid out to the same widths as the lists below.
    private var header: some View {
        HStack(spacing: 0) {
            Text("Menu")
                .frame(width: Self.menuColumnWidth, alignment: .leading)
            Divider()
            Text("Command")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            Divider()
            Text("Key")
                .frame(width: Self.keyColumnWidth, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var lists: some View {
        HStack(spacing: 0) {
            List(groups, id: \.self, selection: $selectedGroup) { group in
                Text(group)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .frame(width: Self.menuColumnWidth)

            Divider()

            List(rows) { entry in
                HStack(spacing: 0) {
                    Text(entry.title)
                    Spacer(minLength: 8)
                    ShortcutField(shortcut: shortcut(for: entry),
                                  onCommit: { commit($0, to: entry) })
                        .frame(width: Self.keyColumnWidth)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            // ponytail: re-identifying the list is the blunt way to show an
            // edited shortcut — it also resets the scroll position. Worth
            // replacing if the command lists ever get long enough to scroll far.
            .id(revision)
        }
    }

    private func shortcut(for entry: KeyBindingCatalog.Entry) -> Shortcut? {
        KeyBindingStore.effective(id: entry.id, default: entry.defaultShortcut)
    }

    /// Validates a typed chord and, if it holds, persists it and retunes the live
    /// menu item. `nil` clears the shortcut, which never conflicts.
    private func commit(_ new: Shortcut?, to entry: KeyBindingCatalog.Entry) {
        if let new, let reason = KeyBindingConflict.rejectionReason(for: new, excluding: entry.item) {
            error = reason
            NSSound.beep()
            return
        }
        error = nil
        KeyBindingStore.setOverride(new, id: entry.id, default: entry.defaultShortcut)
        KeyBindingCatalog.shared.apply(new, toItemWithID: entry.id)
        revision += 1
    }

    private func restoreDefaults() {
        KeyBindingStore.removeAllOverrides()
        KeyBindingCatalog.shared.reapplyAll()
        error = nil
        revision += 1
    }
}

// MARK: - Shortcut field

/// A one-line recorder: shows the current shortcut, and while focused swallows
/// the next chord and reports it.
private struct ShortcutField: NSViewRepresentable {
    let shortcut: Shortcut?
    let onCommit: (Shortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.onCommit = onCommit
    }
}

/// The recorder itself. Kept as a plain NSView rather than an NSTextField: what
/// is being captured is a key equivalent, not text, and a text field would run
/// the chord through the input context first.
final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? { didSet { needsDisplay = true } }
    var onCommit: ((Shortcut?) -> Void)?

    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    // A chord like ⌘B is dispatched as a key equivalent, so it never reaches
    // keyDown — the window offers it to the view hierarchy here first, ahead of
    // the main menu. Claiming it while recording is what lets the user assign a
    // shortcut that some menu item already owns (and be told so).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return false }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, handle(event) else {
            super.keyDown(with: event)
            return
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(Shortcut.allowedModifiers)

        switch event.keyCode {
        case 53:  // Escape — abandon the edit, keep the existing shortcut.
            window?.makeFirstResponder(nil)
            return true
        case 51, 117:  // Delete / Forward Delete — clear the shortcut.
            onCommit?(nil)
            window?.makeFirstResponder(nil)
            return true
        default:
            break
        }

        // charactersIgnoringModifiers still folds Shift into the character
        // ("⇧⌘b" arrives as "B"); `normalized` puts the Shift back in the mask
        // so both spellings compare and display the same way.
        guard let raw = event.charactersIgnoringModifiers, !raw.isEmpty else { return false }
        let candidate = Shortcut(key: raw, modifiers: modifiers).normalized
        onCommit?(candidate)
        window?.makeFirstResponder(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isRecording {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let text = isRecording ? "Type shortcut" : (shortcut?.displayString ?? "")
        let color: NSColor = isRecording ? .selectedMenuItemTextColor
            : (shortcut == nil ? .tertiaryLabelColor : .labelColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
