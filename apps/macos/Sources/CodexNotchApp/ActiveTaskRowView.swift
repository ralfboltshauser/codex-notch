import AppKit
import QuartzCore

final class ActiveTaskRowView: NSView {
    static let rowHeight: CGFloat = 58

    let task: ActiveTask
    private let openHandler: () -> Void
    private let numberBadge: NumberBadgeView
    private let contextLabel: NSTextField
    private let statusLabel: NSTextField
    private var isHovered = false
    private var isTrackingPress = false
    private var isPressed = false

    init(task: ActiveTask, index: Int, theme: NotchTheme, open: @escaping () -> Void) {
        self.task = task
        openHandler = open
        contextLabel = NSTextField(labelWithString: Self.contextText(for: task))
        statusLabel = NSTextField(labelWithString: Self.statusText(for: task))
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
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        let color: NSColor
        switch task.state {
        case .running:
            color = theme.accent
        case .waitingForApproval:
            color = .systemOrange
        case .waitingForInput:
            color = .systemOrange
        case .unavailable:
            color = theme.tertiaryText
        }
        let title = NSTextField(labelWithString: task.title)
        title.font = theme.font(ofSize: 14, weight: .medium)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contextLabel.font = theme.font(ofSize: 10.5, weight: .medium)
        contextLabel.textColor = theme.secondaryText
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.translatesAutoresizingMaskIntoConstraints = false
        contextLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = theme.font(ofSize: 10.5, weight: .semibold)
        statusLabel.textColor = color
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let identity = NSStackView(views: [title, contextLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2
        identity.translatesAutoresizingMaskIntoConstraints = false
        [numberBadge, identity, statusLabel].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.rowHeight),
            numberBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            numberBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            identity.leadingAnchor.constraint(equalTo: numberBadge.trailingAnchor, constant: 11),
            identity.centerYAnchor.constraint(equalTo: centerYAnchor),
            identity.trailingAnchor.constraint(
                lessThanOrEqualTo: statusLabel.leadingAnchor,
                constant: -14
            ),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let openHint = GlobalHotKeys.openShortcutLabel(at: index)
            .map { "Open active task — \($0)" } ?? "Open active task"
        toolTip = openHint
        if task.subagentCount > 0 {
            toolTip = "\(Self.subagentSummary(for: task)). \(openHint) in the parent thread."
        }
        setAccessibilityLabel(
            "Task \(index + 1), \(task.title), \(statusLabel.stringValue), \(contextLabel.stringValue)"
        )
        setAccessibilityHelp("Open this task in Codex")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func setShortcutLetterVisible(_ visible: Bool) { numberBadge.showShortcut(visible) }
    var badgeTextForTesting: String { numberBadge.textForTesting }
    var contextTextForTesting: String { contextLabel.stringValue }
    var statusTextForTesting: String { statusLabel.stringValue }

    override func mouseDown(with event: NSEvent) {
        isTrackingPress = true
        updatePress(at: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        updatePress(at: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        let shouldOpen = paddedHitArea.contains(convert(event.locationInWindow, from: nil))
        isTrackingPress = false
        setPressed(false)
        if shouldOpen { openHandler() }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isPressed { updateBackground() }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    private var paddedHitArea: NSRect { bounds.insetBy(dx: -10, dy: -10) }

    private func updatePress(at event: NSEvent) {
        setPressed(paddedHitArea.contains(convert(event.locationInWindow, from: nil)))
    }

    private func setPressed(_ pressed: Bool) {
        guard isPressed != pressed, let layer else { return }
        isPressed = pressed
        updateBackground()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let target = pressed && !reduceMotion
            ? CATransform3DMakeScale(0.98, 0.98, 1)
            : CATransform3DIdentity
        let current = layer.presentation()?.transform ?? layer.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()

        layer.removeAnimation(forKey: "activeRowPress")
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = pressed ? NotchMotion.pressInDuration : NotchMotion.pressOutDuration
        animation.timingFunction = NotchMotion.easeOut
        layer.add(animation, forKey: "activeRowPress")
    }

    private func updateBackground() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = (isPressed
            ? NSColor.white.withAlphaComponent(0.10)
            : (isHovered ? NSColor.white.withAlphaComponent(0.07) : .clear)).cgColor
        CATransaction.commit()
    }

    private static func contextText(for task: ActiveTask) -> String {
        var parts = [task.sourceLabel]
        if let projectLabel = task.projectLabel { parts.append(projectLabel) }
        if let branch = task.branch { parts.append(branch) }
        if let agentNickname = task.agentNickname {
            parts.append(task.agentRole.map { "\(agentNickname) · \($0)" } ?? agentNickname)
        }
        if task.subagentCount > 0 {
            let label = task.subagentCount == 1 ? "subagent" : "subagents"
            parts.append("\(task.subagentCount) \(label)")
        }
        return parts.joined(separator: "  ·  ")
    }

    private static func statusText(for task: ActiveTask) -> String {
        switch task.state {
        case .running: return "Running"
        case .waitingForApproval: return "Needs approval"
        case .waitingForInput: return "Needs input"
        case .unavailable: return "Connection lost"
        }
    }

    private static func subagentSummary(for task: ActiveTask) -> String {
        var parts = ["\(task.subagentCount) active \(task.subagentCount == 1 ? "subagent" : "subagents")"]
        if task.runningSubagentCount > 0 {
            parts.append("\(task.runningSubagentCount) working")
        }
        if task.attentionSubagentCount > 0 {
            parts.append("\(task.attentionSubagentCount) need attention")
        }
        return parts.joined(separator: ", ")
    }
}
