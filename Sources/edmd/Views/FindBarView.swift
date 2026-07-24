import AppKit

// MARK: - Search field with an inline match count

/// Reserves room on the right of the search text for the count label so the
/// typed text never runs under it.
private final class CountingSearchFieldCell: NSSearchFieldCell {
    var countWidth: CGFloat = 0
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var r = super.searchTextRect(forBounds: rect)
        r.size.width = max(0, r.width - countWidth)
        return r
    }
}

/// An `NSSearchField` that shows the match count inside the field, just left of
/// the cancel (✕) button — the Notes placement.
final class CountingSearchField: NSSearchField {
    private let countLabel = NSTextField(labelWithString: "")

    override class var cellClass: AnyClass? {
        get { CountingSearchFieldCell.self }
        set { }
    }

    /// nil or an empty query hides the count.
    var matchCount: Int? { didSet { updateCount() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.isHidden = true
        addSubview(countLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateCount() {
        if let c = matchCount, !stringValue.isEmpty {
            countLabel.stringValue = "\(c)"
            countLabel.sizeToFit()
            countLabel.isHidden = false
            (cell as? CountingSearchFieldCell)?.countWidth = countLabel.frame.width + 10
        } else {
            countLabel.isHidden = true
            (cell as? CountingSearchFieldCell)?.countWidth = 0
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !countLabel.isHidden else { return }
        let cancel = (cell as? NSSearchFieldCell)?.cancelButtonRect(forBounds: bounds) ?? .zero
        let rightEdge = cancel.width > 0 ? cancel.minX : bounds.maxX - 6
        let w = countLabel.frame.width
        countLabel.frame = NSRect(x: rightEdge - w - 4,
                                  y: (bounds.height - countLabel.frame.height) / 2,
                                  width: w, height: countLabel.frame.height)
    }
}

// MARK: - Find bar

/// The in-document find/replace bar, styled after Apple Notes. Laid out on an
/// `NSGridView` so the search/replace fields share a left edge and the `‹ ›` /
/// `Replace|All` control groups share a left edge. Find-only is one row; toggling
/// Replace reveals a second row and moves **Done** down onto it.
///
/// Dumb view: owns the controls, reports events through closures. All logic is
/// in `FindController`.
final class FindBarView: NSVisualEffectView, NSSearchFieldDelegate {

    let searchField = CountingSearchField()
    let replaceField = NSTextField()

    private let nav = NSSegmentedControl(
        images: [NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!,
                 NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!],
        trackingMode: .momentary, target: nil, action: nil)
    private let replaceToggle = NSButton(checkboxWithTitle: "Replace", target: nil, action: nil)
    private let replaceGroup = NSSegmentedControl(
        labels: ["Replace", "All"], trackingMode: .momentary, target: nil, action: nil)
    // Two Done buttons — one per row — toggled by visibility. Simpler and more
    // robust than moving a single button between grid cells (which failed to
    // render). find-only shows the top one; replace shows the bottom one.
    private let doneTop = NSButton(title: "Done", target: nil, action: nil)
    private let doneBottom = NSButton(title: "Done", target: nil, action: nil)
    /// Row-0 trailing cell: Done (find-only) + the Replace checkbox.
    private let trailing0 = NSStackView()

    private var grid: NSGridView!

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
            grid.row(at: 1).isHidden = !newValue   // hides replace field + group + doneBottom
            doneTop.isHidden = newValue            // Done only on the visible row
            needsLayout = true
        }
    }

    /// The bar's height for the active replace state (drives the content inset).
    var preferredHeight: CGFloat {
        grid.layoutSubtreeIfNeeded()
        return grid.fittingSize.height + 12
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .titlebar
        blendingMode = .withinWindow
        state = .active
        buildUI()
        showsReplaceRow = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    private func buildUI() {
        searchField.placeholderString = "Find"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.searchMenuTemplate = optionsMenu()
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        replaceField.placeholderString = "Replace"
        replaceField.target = self
        replaceField.action = #selector(replaceReturn)
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        nav.target = self
        nav.action = #selector(navClicked)

        replaceGroup.target = self
        replaceGroup.action = #selector(replaceGroupClicked)
        replaceGroup.segmentDistribution = .fit

        for done in [doneTop, doneBottom] {
            done.bezelStyle = .rounded
            done.target = self
            done.action = #selector(doneClicked)
        }

        replaceToggle.target = self
        replaceToggle.action = #selector(replaceToggled)

        trailing0.orientation = .horizontal
        trailing0.spacing = 8
        trailing0.setViews([doneTop, replaceToggle], in: .leading)

        grid = NSGridView(views: [
            [searchField, nav, trailing0],
            [replaceField, replaceGroup, doneBottom],
        ])
        grid.columnSpacing = 8
        grid.rowSpacing = 5
        grid.column(at: 0).xPlacement = .fill        // fields absorb slack
        grid.column(at: 1).xPlacement = .leading      // ‹›/Replace|All share a left edge
        grid.column(at: 2).xPlacement = .trailing
        for r in 0..<grid.numberOfRows { grid.row(at: r).yPlacement = .center }

        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 6),
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

    func setCount(_ count: Int) { searchField.matchCount = count }

    // MARK: - Search-field Return → find next

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { onNext?(); return true }
        return false
    }

    // MARK: - Actions

    @objc private func searchChanged() { onSearchChanged?() }
    @objc private func doneClicked() { onDone?() }
    @objc private func replaceReturn() { onReplace?() }

    @objc private func navClicked() {
        if nav.selectedSegment == 0 { onPrevious?() } else { onNext?() }
    }

    @objc private func replaceGroupClicked() {
        if replaceGroup.selectedSegment == 0 { onReplace?() } else { onReplaceAll?() }
    }

    @objc private func replaceToggled() {
        showsReplaceRow = replaceToggle.state == .on
        onToggleReplace?(showsReplaceRow)
    }

    @objc private func toggleCase() { caseSensitive.toggle(); onOptionsChanged?() }
    @objc private func toggleWholeWord() { wholeWord.toggle(); onOptionsChanged?() }
}
