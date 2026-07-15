import AppKit

final class ActiveTaskRowView: NSView {
    let task: ActiveTask
    private let openHandler: () -> Void
    private let numberBadge: NumberBadgeView

    init(task: ActiveTask, index: Int, theme: NotchTheme, open: @escaping () -> Void) {
        self.task = task
        openHandler = open
        numberBadge = NumberBadgeView(
            number: index + 1,
            shortcut: GlobalHotKeys.openShortcutKeyLabel(at: index),
            theme: theme
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        let stateText: String
        let color: NSColor
        switch task.state {
        case .running:
            stateText = "Running"
            color = theme.accent
        case .waitingForApproval:
            stateText = "Needs approval"
            color = .systemOrange
        case .waitingForInput:
            stateText = "Needs input"
            color = .systemOrange
        case .unavailable:
            stateText = "Connection lost"
            color = theme.tertiaryText
        }
        let title = NSTextField(labelWithString: task.title)
        title.font = theme.font(ofSize: 14, weight: .medium)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let source = NSTextField(labelWithString: task.sourceLabel)
        source.font = theme.font(ofSize: 10.5, weight: .medium)
        source.textColor = theme.secondaryText
        source.lineBreakMode = .byTruncatingTail
        source.translatesAutoresizingMaskIntoConstraints = false
        let status = NSTextField(labelWithString: stateText)
        status.font = theme.font(ofSize: 10.5, weight: .semibold)
        status.textColor = color
        status.translatesAutoresizingMaskIntoConstraints = false
        [numberBadge, title, source, status].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            numberBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            numberBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: numberBadge.trailingAnchor, constant: 11),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            source.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            source.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            source.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.leadingAnchor.constraint(equalTo: source.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = GlobalHotKeys.openShortcutLabel(at: index)
            .map { "Open active task — \($0)" } ?? "Open active task"
        setAccessibilityLabel(
            "Task \(index + 1), \(task.title), \(stateText), \(task.sourceLabel)"
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func setShortcutLetterVisible(_ visible: Bool) { numberBadge.showShortcut(visible) }
    var badgeTextForTesting: String { numberBadge.textForTesting }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { openHandler() }
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }
}
