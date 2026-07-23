import AppKit

/// The in-document find/replace bar, styled after Apple Notes: a full-width
/// strip under the toolbar with a magnifier search field (case / whole-word
/// options in its menu), a live match count, prev/next arrows, a Done button,
/// and a Replace toggle that reveals the replace row.
///
/// This view is dumb: it owns the controls and reports events through closures.
/// All search/replace logic lives in `FindController`.
final class FindBarView: NSVisualEffectView {

    static let findRowHeight: CGFloat = 32
    static let replaceRowHeight: CGFloat = 30

    let searchField = NSSearchField()
    let replaceField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "0")
    private let nav = NSSegmentedControl(
        images: [NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!,
                 NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!],
        trackingMode: .momentary, target: nil, action: nil)
    private let replaceToggle = NSButton(checkboxWithTitle: "Replace", target: nil, action: nil)
    private let replaceRow = NSStackView()

    // Event callbacks, wired by the controller.
    var onSearchChanged: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onDone: (() -> Void)?
    var onToggleReplace: ((Bool) -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onOptionsChanged: (() -> Void)?

    var caseSensitive = false { didSet { syncOptionMenu() } }
    var wholeWord = false { didSet { syncOptionMenu() } }

    var showsReplaceRow: Bool {
        get { replaceToggle.state == .on }
        set {
            replaceToggle.state = newValue ? .on : .off
            replaceRow.isHidden = !newValue
        }
    }

    /// The bar's current height for the active replace state.
    var preferredHeight: CGFloat {
        Self.findRowHeight + (showsReplaceRow ? Self.replaceRowHeight : 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .titlebar
        blendingMode = .withinWindow
        state = .active
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    private func buildUI() {
        searchField.placeholderString = "Find"
        searchField.sendsWholeSearchString = false          // fire per keystroke
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.searchMenuTemplate = optionsMenu()

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        nav.target = self
        nav.action = #selector(navClicked)
        nav.setContentHuggingPriority(.required, for: .horizontal)

        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .rounded
        done.setContentHuggingPriority(.required, for: .horizontal)

        replaceToggle.target = self
        replaceToggle.action = #selector(replaceToggled)
        replaceToggle.setContentHuggingPriority(.required, for: .horizontal)

        let findRow = NSStackView(views: [searchField, countLabel, nav, done, replaceToggle])
        findRow.orientation = .horizontal
        findRow.spacing = 8
        findRow.alignment = .centerY
        findRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal) // takes slack

        // Replace row.
        replaceField.placeholderString = "Replace"
        replaceField.target = self
        replaceField.action = #selector(replaceReturn)
        let replaceBtn = NSButton(title: "Replace", target: self, action: #selector(replaceClicked))
        replaceBtn.bezelStyle = .rounded
        let replaceAllBtn = NSButton(title: "Replace All", target: self, action: #selector(replaceAllClicked))
        replaceAllBtn.bezelStyle = .rounded
        for b in [replaceBtn, replaceAllBtn] { b.setContentHuggingPriority(.required, for: .horizontal) }

        replaceRow.setViews([replaceField, replaceBtn, replaceAllBtn], in: .leading)
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 8
        replaceRow.alignment = .centerY
        replaceRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        replaceRow.isHidden = true

        let column = NSStackView(views: [findRow, replaceRow])
        column.orientation = .vertical
        column.spacing = 0
        column.alignment = .leading
        column.distribution = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            findRow.heightAnchor.constraint(equalToConstant: Self.findRowHeight),
            replaceRow.heightAnchor.constraint(equalToConstant: Self.replaceRowHeight),
            findRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            replaceRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    private func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        let cs = NSMenuItem(title: "Case Sensitive", action: #selector(toggleCase), keyEquivalent: "")
        cs.target = self
        let ww = NSMenuItem(title: "Whole Words", action: #selector(toggleWholeWord), keyEquivalent: "")
        ww.target = self
        menu.addItem(cs); menu.addItem(ww)
        return menu
    }

    private func syncOptionMenu() {
        guard let menu = searchField.searchMenuTemplate else { return }
        menu.items.first { $0.action == #selector(toggleCase) }?.state = caseSensitive ? .on : .off
        menu.items.first { $0.action == #selector(toggleWholeWord) }?.state = wholeWord ? .on : .off
    }

    // MARK: - Display

    func setCount(_ count: Int) {
        countLabel.stringValue = "\(count)"
    }

    // MARK: - Actions

    @objc private func searchChanged() { onSearchChanged?() }
    @objc private func doneClicked() { onDone?() }
    @objc private func replaceClicked() { onReplace?() }
    @objc private func replaceReturn() { onReplace?() }
    @objc private func replaceAllClicked() { onReplaceAll?() }

    @objc private func navClicked() {
        if nav.selectedSegment == 0 { onPrevious?() } else { onNext?() }
    }

    @objc private func replaceToggled() {
        let on = replaceToggle.state == .on
        replaceRow.isHidden = !on
        onToggleReplace?(on)
    }

    @objc private func toggleCase() {
        caseSensitive.toggle()
        onOptionsChanged?()
    }

    @objc private func toggleWholeWord() {
        wholeWord.toggle()
        onOptionsChanged?()
    }
}
