import AppKit
import QuartzCore

final class FocuslessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ClosureButton: NSButton {
    var handler: (() -> Void)?

    init(handler: (() -> Void)? = nil) {
        self.handler = handler
        super.init(frame: .zero)
        target = self
        action = #selector(pressed)
        isBordered = false
        refusesFirstResponder = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { handler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class HUDContentView: NSView {
    private static let pitchBlack = CGColor(gray: 0, alpha: 1)

    var onHoverChanged: ((Bool) -> Void)?
    var controls: [NSView] = []
    var shoulderHeight: CGFloat = 32 { didSet { needsLayout = true } }
    var shoulderInset: CGFloat = 34 { didSet { needsLayout = true } }
    private var tracking: NSTrackingArea?
    private let shapeMask = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.pitchBlack
        layer?.opacity = 1
        shapeMask.fillColor = Self.pitchBlack
        layer?.mask = shapeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let path = islandPath(in: bounds)
        shapeMask.frame = bounds
        shapeMask.path = path
    }

    private func islandPath(in rect: NSRect) -> CGPath {
        let path = CGMutablePath()
        let width = rect.width
        let height = rect.height
        // Put the mathematical edge outside the clipped layer. An edge exactly
        // at maxY gets anti-aliased into a one-pixel gray seam on bright desktops.
        let top = height + 2
        let inset = min(shoulderInset, width / 4)
        let shoulderBottom = max(32, height - shoulderHeight)
        let bottomRadius = min(CGFloat(28), (width - inset * 2) / 4)
        let left = inset
        let right = width - inset

        // The whole top edge is black and clipped by the display boundary. The
        // body then narrows through these shoulders, like one oversized notch.
        path.move(to: CGPoint(x: 0, y: top))
        path.addLine(to: CGPoint(x: width, y: top))
        path.addCurve(
            to: CGPoint(x: right, y: shoulderBottom),
            control1: CGPoint(x: width - inset * 0.52, y: top),
            control2: CGPoint(x: right, y: height - shoulderHeight * 0.46)
        )
        path.addLine(to: CGPoint(x: right, y: bottomRadius))
        path.addCurve(
            to: CGPoint(x: right - bottomRadius, y: 0),
            control1: CGPoint(x: right, y: bottomRadius * 0.45),
            control2: CGPoint(x: right - bottomRadius * 0.45, y: 0)
        )
        path.addLine(to: CGPoint(x: left + bottomRadius, y: 0))
        path.addCurve(
            to: CGPoint(x: left, y: bottomRadius),
            control1: CGPoint(x: left + bottomRadius * 0.45, y: 0),
            control2: CGPoint(x: left, y: bottomRadius * 0.45)
        )
        path.addLine(to: CGPoint(x: left, y: shoulderBottom))
        path.addCurve(
            to: CGPoint(x: 0, y: top),
            control1: CGPoint(x: left, y: height - shoulderHeight * 0.46),
            control2: CGPoint(x: inset * 0.52, y: top)
        )
        path.closeSubpath()
        return path
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            controls.forEach { $0.animator().alphaValue = 1 }
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            controls.forEach { $0.animator().alphaValue = 0 }
        }
    }
}

final class NumberBadgeView: NSView {
    init(number: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        let label = NSTextField(labelWithString: "\(number)")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.82)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class TaskRowView: NSView {
    private let openHandler: () -> Void
    private let dismissButton: ClosureButton
    private var tracking: NSTrackingArea?

    init(task: CompletedTask, index: Int, open: @escaping () -> Void, dismiss: @escaping () -> Void) {
        openHandler = open
        dismissButton = ClosureButton(handler: dismiss)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12

        let number = NumberBadgeView(number: index + 1)

        let title = NSTextField(labelWithString: task.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = NSColor.white.withAlphaComponent(0.94)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let source = NSTextField(labelWithString: task.sourceLabel)
        source.font = .systemFont(ofSize: 10.5, weight: .medium)
        source.textColor = NSColor.white.withAlphaComponent(0.38)
        source.lineBreakMode = .byTruncatingTail
        source.translatesAutoresizingMaskIntoConstraints = false
        source.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let shortcut = NSTextField(labelWithString: "⌃⇧\(index + 1)")
        shortcut.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcut.textColor = NSColor.white.withAlphaComponent(0.38)
        shortcut.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss task")
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        dismissButton.toolTip = "Dismiss — ⌥⇧\(index + 1)"
        dismissButton.alphaValue = 0
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        [number, title, source, shortcut, dismissButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            number.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 11),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            source.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 14),
            source.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            source.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcut.leadingAnchor.constraint(equalTo: source.trailingAnchor, constant: 12),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.leadingAnchor.constraint(equalTo: shortcut.trailingAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { openHandler() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor
        dismissButton.animator().alphaValue = 1
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        dismissButton.animator().alphaValue = 0
    }
}

final class OverlayController {
    static let eventVisibilityDuration: TimeInterval = 5

    private let panel: FocuslessPanel
    private var tasks: [CompletedTask] = []
    private var hideTimer: Timer?
    private var targetScreen: NSScreen?
    private var isPinned = false
    private var currentBodyInset: CGFloat = 0
    private var transitionID = 0

    var onOpen: ((Int) -> Void)?
    var onDismiss: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: (() -> Void)?
    var frameForTesting: NSRect { panel.frame }
    var bodyHeightForTesting: CGFloat { panel.frame.height }
    var bodyWidthForTesting: CGFloat { panel.frame.width - currentBodyInset * 2 }
    var eventVisibilityDurationForTesting: TimeInterval { Self.eventVisibilityDuration }
    var isPinnedForTesting: Bool { isPinned }
    var hasHideTimerForTesting: Bool { hideTimer?.isValid == true }
    var isVisibleForTesting: Bool { panel.isVisible }
    var panelAlphaForTesting: CGFloat { panel.alphaValue }
    var contentViewForTesting: NSView? { panel.contentView }

    init() {
        panel = FocuslessPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.positionPanel() }
    }

    func update(tasks: [CompletedTask]) {
        self.tasks = tasks
        rebuildContent()
        if tasks.isEmpty { hide(immediately: true) }
        else if panel.isVisible { positionPanel() }
    }

    func showForEvent() {
        guard !tasks.isEmpty else { return }
        if !panel.isVisible { targetScreen = screenUnderPointer() }
        let remainsPinned = panel.isVisible && isPinned
        present(autoHide: !remainsPinned)
    }

    private func present(autoHide: Bool) {
        guard !tasks.isEmpty else { return }
        transitionID &+= 1
        let wasVisible = panel.isVisible
        rebuildContent()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        positionPanel()
        hideTimer?.invalidate()

        if !wasVisible {
            // The island must always composite as literal black. Fading the
            // panel would blend it with the desktop and turn it gray.
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            if !reduceMotion { animateContentTranslation(from: 18, to: 0, duration: 0.20) }
        }
        if autoHide { scheduleHide(after: Self.eventVisibilityDuration) }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            targetScreen = screenUnderPointer()
            isPinned = true
            present(autoHide: false)
        }
    }

    func hide(immediately: Bool = false) {
        hideTimer?.invalidate()
        isPinned = false
        transitionID &+= 1
        let hidingTransitionID = transitionID
        guard panel.isVisible else { return }
        if immediately {
            panel.orderOut(nil)
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.orderOut(nil)
            return
        }
        animateContentTranslation(from: 0, to: 12, duration: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.transitionID == hidingTransitionID else { return }
            self.panel.orderOut(nil)
        }
    }

    private func rebuildContent() {
        let screen = targetScreen ?? screenUnderPointer()
        let geometry = islandGeometry(for: screen)
        currentBodyInset = geometry.shoulderInset
        let root = HUDContentView()
        root.shoulderHeight = geometry.shoulderHeight
        root.shoulderInset = geometry.shoulderInset

        let codexIcon = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Codex tasks ready"
        ) ?? NSImage())
        codexIcon.contentTintColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        codexIcon.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "CODEX")
        heading.font = .systemFont(ofSize: 11, weight: .bold)
        heading.textColor = NSColor.white.withAlphaComponent(0.72)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "\(tasks.count) READY")
        count.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        count.textColor = NSColor.white.withAlphaComponent(0.32)
        count.translatesAutoresizingMaskIntoConstraints = false

        let toggleHint = NSTextField(labelWithString: "⌃⇧0")
        toggleHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        toggleHint.textColor = NSColor.white.withAlphaComponent(0.38)
        toggleHint.translatesAutoresizingMaskIntoConstraints = false

        let clear = ClosureButton { [weak self] in self?.onClear?() }
        clear.title = "Clear"
        clear.font = .systemFont(ofSize: 11, weight: .medium)
        clear.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        clear.toolTip = "Dismiss all tasks"
        clear.alphaValue = 0
        clear.translatesAutoresizingMaskIntoConstraints = false
        let settings = ClosureButton { [weak self] in self?.onSettings?() }
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settings.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        settings.toolTip = "Connection settings"
        settings.alphaValue = 0
        settings.translatesAutoresizingMaskIntoConstraints = false
        root.controls = [clear, settings]

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        [codexIcon, heading, count, toggleHint, clear, settings].forEach(header.addSubview)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 44),
            codexIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 13),
            codexIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            codexIcon.widthAnchor.constraint(equalToConstant: 17),
            codexIcon.heightAnchor.constraint(equalToConstant: 17),
            heading.leadingAnchor.constraint(equalTo: codexIcon.trailingAnchor, constant: 8),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 8),
            count.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.leadingAnchor.constraint(greaterThanOrEqualTo: count.trailingAnchor, constant: 12),
            settings.leadingAnchor.constraint(equalTo: clear.trailingAnchor, constant: 6),
            toggleHint.leadingAnchor.constraint(equalTo: settings.trailingAnchor, constant: 10),
            toggleHint.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            toggleHint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            settings.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            settings.widthAnchor.constraint(equalToConstant: 24),
            settings.heightAnchor.constraint(equalToConstant: 24),
            clear.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)

        for (index, task) in tasks.enumerated() {
            let row = TaskRowView(
                task: task,
                index: index,
                open: { [weak self] in self?.onOpen?(index) },
                dismiss: { [weak self] in self?.onDismiss?(index) }
            )
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: geometry.shoulderInset + 7
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -(geometry.shoulderInset + 7)
            ),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -7),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        root.onHoverChanged = { [weak self] hovering in
            if hovering { self?.hideTimer?.invalidate() }
            else if self?.isPinned == false {
                self?.scheduleHide(after: Self.eventVisibilityDuration)
            }
        }
        panel.contentView = root
        let height = CGFloat(56 + tasks.count * 50)
        let size = NSSize(width: geometry.windowWidth, height: height)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)
    }

    private func positionPanel() {
        panel.setFrameOrigin(visibleOrigin())
    }

    private func animateContentTranslation(
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval
    ) {
        guard let layer = panel.contentView?.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(
            name: to == 0 ? .easeOut : .easeIn
        )
        layer.add(animation, forKey: "notchTranslation")
    }

    private func visibleOrigin() -> NSPoint {
        let screen = targetScreen ?? screenUnderPointer()
        let frame = screen.frame
        return NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height
        )
    }

    private func islandGeometry(
        for screen: NSScreen
    ) -> (windowWidth: CGFloat, shoulderInset: CGFloat, shoulderHeight: CGFloat) {
        let menuOrNotchHeight = max(
            screen.safeAreaInsets.top,
            screen.frame.maxY - screen.visibleFrame.maxY
        )
        let shoulderInset: CGFloat = 34
        let bodyWidth = min(820, max(460, screen.frame.width - 160))
        return (
            windowWidth: bodyWidth + shoulderInset * 2,
            shoulderInset: shoulderInset,
            shoulderHeight: max(28, menuOrNotchHeight)
        )
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func scheduleHide(after interval: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}
