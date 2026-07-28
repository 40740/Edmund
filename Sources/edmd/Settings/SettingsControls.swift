// Shared Settings view helpers.

import SwiftUI

/// The shared surface color for Settings boxes — the Syntax list, the Key
/// Bindings nav/header/table, the Extensions panel.
///
/// `.controlBackgroundColor` is what the Key Bindings nav list already drew by
/// default, and it is the color the rest of Settings is matched to. Notably it
/// is *not* the editor's canvas color: Settings is chrome, not document
/// surface, and matching the document made the boxes read as editable content.
extension View {
    func settingsSurfaceBackground() -> some View {
        background(Color(nsColor: .controlBackgroundColor))
    }
}

extension View {
    /// Consistent pane padding: CotEditor-style breathing room (scene padding at
    /// the top, a little more on the sides and bottom).
    func settingsPanePadding() -> some View {
        self.padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
            .frame(width: 600, alignment: .leading)
            // Don't auto-focus (and draw a focus ring around) the first control
            // when a pane opens — Settings has no use for keyboard-focus rings.
            .focusEffectDisabled()
    }
}
