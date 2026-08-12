import AppKit

extension EditorTextView {

    /// Swallow the system "invalid key" beep.
    ///
    /// When a key combination isn't bound to any action, AppKit routes it to
    /// `NSResponder.noop(_:)`, which `NSTextView` answers by playing the alert
    /// sound (the "按错键 / beep on a stray keystroke"). In a Markdown editor a
    /// lot of combos intentionally have no command (there is no menu item to
    /// trigger), so beeping on every stray combination is just noise. We consume
    /// the no-op here instead of forwarding it, so unbound keys are silently
    /// ignored while every real editing command still flows through `super`.
    public override func doCommand(by selector: Selector) {
        // `noop:` is the command AppKit routes unbound key combinations to. It
        // isn't exposed as a Swift method on NSResponder, so match it by raw
        // selector string.
        if selector == Selector("noop:") {
            return
        }
        super.doCommand(by: selector)
    }
}
