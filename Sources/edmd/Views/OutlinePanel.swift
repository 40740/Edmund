import AppKit
import EdmundCore

// MARK: - Document Outline (TOC) Panel
//
// A hover-revealed navigation panel pinned to the window's right edge.
//
// Design goals (all in service of the "instant open / 秒开" contract):
//   • When collapsed it is just a thin (16pt) transparent hover strip along the
//     right edge — it draws nothing and costs nothing at launch.
//   • The heading list is parsed on demand, only while visible, from the same
//     `rawSource` the editor already holds (no second copy). Extracting ATX
//     headings is an O(lines) line scan (`EditorTextView.outlineHeadings`).
//   • Clicking a heading navigates via the editor's existing scroll path.
//   • Headings are indented by ATX level so the outline shows the document's
//     nesting at a glance.

/// Hover-reveal outline. Always present as a thin right-edge strip; expanding
/// the frame to `panelWidth` (and revealing the table) on hover. Its own frame
/// is managed here so the document only pins its right edge and provides a
/// container width via `setContainerWidth(_:)`.
final class OutlinePanel: NSView, NSTableViewDataSource, NSTableViewDelegate {

    /// Called with the source offset of a heading to scroll the editor to it.
    var onNavigate: ((Int) -> Void)?
    /// Called when the panel is revealed so the owning document can feed it a
    /// fresh outline (parsed only now, on demand).
    var onRequestOutline: (() -> Void)?

    /// Width of the collapsed hover-detection strip on the right edge.
    static let hoverStripWidth: CGFloat = 16
    /// Panel width once revealed.
    static let panelWidth: CGFloat = 220

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var entries: [EditorTextView.OutlineHeading] = []

    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isRevealed = false
    /// The superview's width, used to keep the panel pinned to the right edge
    /// as it expands/collapses. Kept in sync by the document on resize.
    private var containerWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0

        let column = NSTableColumn(identifier: .init("heading"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(navigateClickedRow(_:))
        table.doubleAction = #selector(navigateClickedRow(_:))

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.isHidden = true   // only shown while revealed

        addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public API

    /// Keeps the panel pinned to the right edge of a `containerWidth`-wide
    /// superview (called by the document on layout).
    func setContainerWidth(_ width: CGFloat) {
        containerWidth = width
        applyFrame(animated: false)
    }

    /// Updates the panel's heading entries. Called by the document when the
    /// panel is visible and the text changes; also used on reveal.
    func update(outline: [EditorTextView.OutlineHeading]) {
        entries = outline
        table.reloadData()
    }

    // MARK: - Hover tracking (right edge reveal)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        // Track the panel's whole bounds: the thin strip when collapsed, the
        // full panel once revealed. `inVisibleRect` keeps it in sync as we resize.
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeInActiveApp,
                                          .mouseMoved, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        reveal()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        // A small grace delay so moving the pointer a couple of pixels off the
        // edge (e.g. to grab the scroller) doesn't flash the panel away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isPointerInside else { return }
            self.hide()
        }
    }

    private func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
        scroll.isHidden = false
        applyFrame(animated: true)
        onRequestOutline?()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    private func hide() {
        guard isRevealed else { return }
        isRevealed = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, !self.isRevealed else { return }
            self.scroll.isHidden = true
            self.applyFrame(animated: false)
        }
    }

    /// Positions the panel pinned to the right edge at the collapsed or revealed
    /// width. Autoresizing keeps the right edge fixed during window resize; this
    /// only animates the collapse/expand.
    private func applyFrame(animated: Bool) {
        guard containerWidth > 0, let superview = superview else { return }
        let width = isRevealed ? Self.panelWidth : Self.hoverStripWidth
        let newFrame = NSRect(x: superview.bounds.maxX - width, y: 0,
                              width: width, height: superview.bounds.height)
        guard abs(newFrame.width - frame.width) > 0.5 || abs(newFrame.maxX - frame.maxX) > 0.5 else {
            return
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().frame = newFrame
            }
        } else {
            frame = newFrame
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let entry = entries[row]
        let identifier = NSUserInterfaceItemIdentifier("OutlineCell")
        let cell: OutlineCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? OutlineCellView {
            cell = reused
        } else {
            cell = OutlineCellView()
            cell.identifier = identifier
        }
        // Indent by ATX level for a nested outline look.
        cell.leadingInset = 6 + CGFloat(max(0, entry.level - 1)) * 14
        cell.title = entry.text
        cell.isEmphasis = entry.level <= 2
        return cell
    }

    // MARK: - Row click

    @objc private func navigateClickedRow(_ sender: Any?) {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0, row < entries.count else { return }
        onNavigate?(entries[row].offset)
        // Clicking is a deliberate jump; hide the panel so it doesn't cover text.
        hide()
    }
}

/// Reusable cell for one outline entry. Keeps its own field + leading-constraint
/// so indentation can be updated per row without stacking duplicate constraints
/// on reuse.
private final class OutlineCellView: NSTableCellView {
    private let field = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?

    var title: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var isEmphasis: Bool {
        get { field.font == NSFont.boldSystemFont(ofSize: 12) }
        set { field.font = newValue ? NSFont.boldSystemFont(ofSize: 12)
                                     : NSFont.systemFont(ofSize: 12) }
    }

    /// Left inset in points; drives the per-level indentation. Updates the one
    /// shared leading constraint instead of adding new ones each reuse.
    var leadingInset: CGFloat {
        get { leadingConstraint?.constant ?? 6 }
        set {
            if let c = leadingConstraint {
                c.constant = newValue
            } else {
                let c = field.leadingAnchor.constraint(equalTo: leadingAnchor,
                                                       constant: newValue)
                c.isActive = true
                leadingConstraint = c
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        textField = field
        NSLayoutConstraint.activate([
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        leadingInset = 6
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
