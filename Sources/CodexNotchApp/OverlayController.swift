import AppKit
import QuartzCore

private enum NotchMotion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static let eventOpenDuration: TimeInterval = 0.24
    static let shortcutOpenDuration: TimeInterval = 0.16
    static let closeDuration: TimeInterval = 0.17
    static let launchDuration: TimeInterval = 0.18
}

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
    var bodyInset: CGFloat = 34 { didSet { needsLayout = true } }
    var notchWidth: CGFloat = 128 { didSet { needsLayout = true } }
    var notchHeight: CGFloat = 28 { didSet { needsLayout = true } }
    var notchCenterOffset: CGFloat = 0 { didSet { needsLayout = true } }

    private var tracking: NSTrackingArea?
    private let shapeMask = CAShapeLayer()
    private var targetExpansion: CGFloat = 0
    private weak var contentHost: NSView?
    private weak var headerView: NSView?
    private var taskRows: [TaskRowView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.pitchBlack
        layer?.opacity = 1
        shapeMask.fillColor = Self.pitchBlack
        layer?.mask = shapeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureMotion(contentHost: NSView, header: NSView, rows: [TaskRowView]) {
        self.contentHost = contentHost
        headerView = header
        taskRows = rows
        contentHost.wantsLayer = true
        header.wantsLayer = true
        rows.forEach { $0.wantsLayer = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = islandPath(in: bounds, expansion: targetExpansion)
        CATransaction.commit()
    }

    func setInitialState(expanded: Bool) {
        targetExpansion = expanded ? 1 : 0
        layoutSubtreeIfNeeded()
        let opacity: Float = expanded ? 1 : 0
        let transform = expanded
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, 6, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.removeAllAnimations()
        shapeMask.path = islandPath(in: bounds, expansion: targetExpansion)
        contentHost?.layer?.removeAllAnimations()
        contentHost?.layer?.opacity = opacity
        contentHost?.layer?.transform = transform
        CATransaction.commit()
    }

    func animateExpansion(expanded: Bool, duration: TimeInterval) {
        layoutSubtreeIfNeeded()
        let target: CGFloat = expanded ? 1 : 0
        let targetPath = islandPath(in: bounds, expansion: target)
        let currentPath = shapeMask.presentation()?.path ?? shapeMask.path ?? targetPath
        targetExpansion = target

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = targetPath
        CATransaction.commit()

        shapeMask.removeAnimation(forKey: "notchShape")
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = currentPath
        animation.toValue = targetPath
        animation.duration = duration
        animation.timingFunction = NotchMotion.easeOut
        shapeMask.add(animation, forKey: "notchShape")
    }

    func animateContentIn(duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: 1,
            transform: CATransform3DIdentity,
            duration: duration
        )
    }

    func animateContentOut(duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: 0,
            transform: CATransform3DMakeTranslation(0, 4, 0),
            duration: duration
        )
    }

    func animateLaunch(selectedRow: TaskRowView?) {
        if let headerView {
            animate(
                view: headerView,
                opacity: 0,
                transform: CATransform3DMakeTranslation(0, 3, 0),
                duration: 0.07
            )
        }
        taskRows.forEach { $0.animateForLaunch(selected: $0 === selectedRow) }
    }

    private func animate(
        view: NSView,
        opacity: Float,
        transform: CATransform3D,
        duration: TimeInterval
    ) {
        guard let layer = view.layer else { return }
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        layer.transform = transform
        CATransaction.commit()

        layer.removeAnimation(forKey: "notchContent")
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = currentOpacity
        opacityAnimation.toValue = opacity
        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = currentTransform
        transformAnimation.toValue = transform

        let group = CAAnimationGroup()
        group.animations = [opacityAnimation, transformAnimation]
        group.duration = duration
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "notchContent")
    }

    private func islandPath(in rect: NSRect, expansion: CGFloat) -> CGPath {
        let progress = min(1, max(0, expansion))
        let width = rect.width
        let height = rect.height
        let top = height + 2
        let center = min(
            width - notchWidth / 2 - 12,
            max(notchWidth / 2 + 12, width / 2 + notchCenterOffset)
        )
        let neckHalfWidth = min(notchWidth / 2, width / 2 - 20)
        let neckLeft = center - neckHalfWidth
        let neckRight = center + neckHalfWidth
        let neckBottom = max(0, height - notchHeight)
        let closedRadius = min(CGFloat(10), min(notchHeight * 0.38, neckHalfWidth / 2))
        let expandedRadius = min(CGFloat(26), (width - bodyInset * 2) / 4)
        let bottomRadius = interpolate(closedRadius, expandedRadius, progress)
        let bodyLeft = interpolate(neckLeft, bodyInset, progress)
        let bodyRight = interpolate(neckRight, width - bodyInset, progress)
        let bodyBottom = interpolate(neckBottom, 0, progress)
        let neckEdgeBottom = interpolate(neckBottom + closedRadius, neckBottom + 4, progress)
        let shoulderBottom = interpolate(
            neckBottom + closedRadius,
            max(bodyBottom + bottomRadius, neckBottom - 18),
            progress
        )

        let path = CGMutablePath()
        path.move(to: CGPoint(x: neckLeft, y: top))
        path.addLine(to: CGPoint(x: neckRight, y: top))
        path.addLine(to: CGPoint(x: neckRight, y: neckEdgeBottom))
        path.addCurve(
            to: CGPoint(x: bodyRight, y: shoulderBottom),
            control1: CGPoint(
                x: neckRight,
                y: interpolate(neckEdgeBottom, neckBottom - 2, progress)
            ),
            control2: CGPoint(
                x: bodyRight,
                y: shoulderBottom + 8 * progress
            )
        )
        path.addLine(to: CGPoint(x: bodyRight, y: bodyBottom + bottomRadius))
        path.addCurve(
            to: CGPoint(x: bodyRight - bottomRadius, y: bodyBottom),
            control1: CGPoint(x: bodyRight, y: bodyBottom + bottomRadius * 0.45),
            control2: CGPoint(x: bodyRight - bottomRadius * 0.45, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: bodyLeft + bottomRadius, y: bodyBottom))
        path.addCurve(
            to: CGPoint(x: bodyLeft, y: bodyBottom + bottomRadius),
            control1: CGPoint(x: bodyLeft + bottomRadius * 0.45, y: bodyBottom),
            control2: CGPoint(x: bodyLeft, y: bodyBottom + bottomRadius * 0.45)
        )
        path.addLine(to: CGPoint(x: bodyLeft, y: shoulderBottom))
        path.addCurve(
            to: CGPoint(x: neckLeft, y: neckEdgeBottom),
            control1: CGPoint(
                x: bodyLeft,
                y: shoulderBottom + 8 * progress
            ),
            control2: CGPoint(
                x: neckLeft,
                y: interpolate(neckEdgeBottom, neckBottom - 2, progress)
            )
        )
        path.addLine(to: CGPoint(x: neckLeft, y: top))
        path.closeSubpath()
        return path
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
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
            context.duration = 0.12
            context.timingFunction = NotchMotion.easeOut
            controls.forEach { $0.animator().alphaValue = 1 }
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = NotchMotion.easeOut
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
        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.86)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class TaskRowView: NSView {
    let task: CompletedTask

    private let openHandler: () -> Void
    private let dismissButton: ClosureButton
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isTrackingPress = false
    private var isPressed = false

    init(task: CompletedTask, index: Int, open: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.task = task
        openHandler = open
        dismissButton = ClosureButton(handler: dismiss)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        let number = NumberBadgeView(number: index + 1)

        let title = NSTextField(labelWithString: task.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = NSColor.white.withAlphaComponent(0.95)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let source = NSTextField(labelWithString: task.sourceLabel)
        source.font = .systemFont(ofSize: 10.5, weight: .medium)
        source.textColor = NSColor.white.withAlphaComponent(0.56)
        source.lineBreakMode = .byTruncatingTail
        source.translatesAutoresizingMaskIntoConstraints = false
        source.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let shortcut = NSTextField(labelWithString: "⌃⇧\(index + 1)")
        shortcut.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcut.textColor = NSColor.white.withAlphaComponent(0.52)
        shortcut.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss task")
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.66)
        dismissButton.toolTip = "Dismiss — ⌥⇧\(index + 1)"
        dismissButton.alphaValue = 0
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        [number, title, source, shortcut, dismissButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
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

    private var paddedHitArea: NSRect { bounds.insetBy(dx: -10, dy: -10) }

    private func updatePress(at event: NSEvent) {
        setPressed(paddedHitArea.contains(convert(event.locationInWindow, from: nil)))
    }

    private func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed
        updateAppearance(duration: pressed ? 0.08 : 0.12)
    }

    private func updateAppearance(duration: TimeInterval) {
        guard let layer else { return }
        let targetBackground = NSColor.white.withAlphaComponent(
            isPressed ? 0.13 : (isHovered ? 0.075 : 0)
        ).cgColor
        let targetTransform = isPressed
            ? CATransform3DMakeScale(0.985, 0.985, 1)
            : CATransform3DIdentity
        let currentBackground = layer.presentation()?.backgroundColor
            ?? layer.backgroundColor
            ?? NSColor.clear.cgColor
        let currentTransform = layer.presentation()?.transform ?? layer.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = targetBackground
        layer.transform = targetTransform
        CATransaction.commit()

        layer.removeAnimation(forKey: "rowPress")
        let background = CABasicAnimation(keyPath: "backgroundColor")
        background.fromValue = currentBackground
        background.toValue = targetBackground
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = currentTransform
        transform.toValue = targetTransform
        let group = CAAnimationGroup()
        group.animations = [background, transform]
        group.duration = duration
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "rowPress")
    }

    func animateForLaunch(selected: Bool) {
        guard let layer else { return }
        let targetTransform = CATransform3DMakeTranslation(0, selected ? 6 : 3, 0)
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let duration: TimeInterval = selected ? 0.12 : 0.07
        let delay: TimeInterval = selected ? 0.025 : 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = targetTransform
        if selected {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        }
        CATransaction.commit()

        layer.removeAllAnimations()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = currentOpacity
        opacity.toValue = 0
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = currentTransform
        transform.toValue = targetTransform
        let group = CAAnimationGroup()
        group.animations = [opacity, transform]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = duration
        group.fillMode = .backwards
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "rowLaunch")
    }

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
        isHovered = true
        updateAppearance(duration: 0.10)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = NotchMotion.easeOut
            dismissButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isPressed { updateAppearance(duration: 0.12) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = NotchMotion.easeOut
            dismissButton.animator().alphaValue = 0
        }
    }
}

private struct IslandGeometry {
    let windowWidth: CGFloat
    let bodyInset: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchCenterOffset: CGFloat
}

final class OverlayController {
    static let eventVisibilityDuration: TimeInterval = 5

    private enum Phase {
        case hidden
        case opening
        case open
        case closing
        case launching
    }

    private let panel: FocuslessPanel
    private var tasks: [CompletedTask] = []
    private var hideTimer: Timer?
    private var targetScreen: NSScreen?
    private var isPinned = false
    private var currentBodyInset: CGFloat = 0
    private var currentNotchWidth: CGFloat = 0
    private var currentNotchHeight: CGFloat = 0
    private var transitionID = 0
    private var phase: Phase = .hidden
    private var pendingRebuild = false
    private var updateVersion: String?
    private weak var updateButton: ClosureButton?
    private weak var rootView: HUDContentView?
    private var rowsByEventID: [String: TaskRowView] = [:]

    var onOpen: ((CompletedTask) -> Bool)?
    var onOpenFinished: ((CompletedTask) -> Void)?
    var onDismiss: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: (() -> Void)?
    var onUpdate: (() -> Void)?
    var frameForTesting: NSRect { panel.frame }
    var bodyHeightForTesting: CGFloat { panel.frame.height }
    var bodyWidthForTesting: CGFloat { panel.frame.width - currentBodyInset * 2 }
    var notchWidthForTesting: CGFloat { currentNotchWidth }
    var notchHeightForTesting: CGFloat { currentNotchHeight }
    var eventVisibilityDurationForTesting: TimeInterval { Self.eventVisibilityDuration }
    var isPinnedForTesting: Bool { isPinned }
    var hasHideTimerForTesting: Bool { hideTimer?.isValid == true }
    var isVisibleForTesting: Bool { panel.isVisible }
    var isLaunchingForTesting: Bool { phase == .launching }
    var panelAlphaForTesting: CGFloat { panel.alphaValue }
    var contentViewForTesting: NSView? { panel.contentView }
    var isUpdateAvailableForTesting: Bool { updateVersion != nil }
    var updateButtonForTesting: NSButton? { updateButton }
    var hasContent: Bool { !tasks.isEmpty || updateVersion != nil }

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
        ) { [weak self] _ in self?.screenParametersDidChange() }
    }

    func update(tasks: [CompletedTask]) {
        self.tasks = tasks
        if !hasContent, phase != .launching {
            hide(immediately: true)
            rebuildContent(initiallyExpanded: false)
            return
        }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func setUpdateAvailable(version: String?) {
        let wasAvailable = updateVersion != nil
        updateVersion = version
        if !hasContent, phase != .launching {
            hide(immediately: true)
            rebuildContent(initiallyExpanded: false)
            return
        }

        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }

        if version != nil, !wasAvailable { showForEvent() }
    }

    func showForEvent() {
        guard hasContent else { return }
        if phase == .hidden { targetScreen = screenUnderPointer() }
        if phase == .open || phase == .opening {
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }
        present(autoHide: !isPinned, duration: NotchMotion.eventOpenDuration)
    }

    func toggle() {
        switch phase {
        case .hidden:
            targetScreen = screenUnderPointer()
            isPinned = true
            present(autoHide: false, duration: NotchMotion.shortcutOpenDuration)
        case .closing:
            isPinned = true
            present(autoHide: false, duration: NotchMotion.shortcutOpenDuration)
        case .launching:
            break
        case .opening, .open:
            hide()
        }
    }

    func openTask(at index: Int) {
        guard tasks.indices.contains(index) else { return }
        openTask(tasks[index])
    }

    func hide(immediately: Bool = false) {
        hideTimer?.invalidate()
        isPinned = false
        transitionID &+= 1
        let hidingTransitionID = transitionID
        guard phase != .hidden || panel.isVisible else { return }

        if immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            rootView?.setInitialState(expanded: false)
            panel.orderOut(nil)
            phase = .hidden
            finishPendingRebuild(expanded: false)
            return
        }
        guard phase != .launching else { return }

        phase = .closing
        rootView?.animateContentOut(duration: 0.10)
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.closeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.closeDuration) { [weak self] in
            guard let self, self.transitionID == hidingTransitionID else { return }
            self.panel.orderOut(nil)
            self.phase = .hidden
            self.finishPendingRebuild(expanded: false)
        }
    }

    private func present(autoHide: Bool, duration: TimeInterval) {
        guard hasContent else { return }
        if phase == .open || phase == .opening {
            if autoHide { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }

        transitionID &+= 1
        let presentingTransitionID = transitionID
        let wasHidden = phase == .hidden || !panel.isVisible
        if rootView == nil { rebuildContent(initiallyExpanded: false) }
        positionPanel()
        hideTimer?.invalidate()
        panel.alphaValue = 1
        if wasHidden { panel.orderFrontRegardless() }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        phase = .opening
        if reduceMotion {
            rootView?.setInitialState(expanded: true)
        } else {
            rootView?.animateExpansion(expanded: true, duration: duration)
            rootView?.animateContentIn(duration: min(0.16, duration))
        }

        let completionDelay = reduceMotion ? 0 : duration
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
            guard let self, self.transitionID == presentingTransitionID else { return }
            self.phase = .open
            self.finishPendingRebuild(expanded: true)
        }
        if autoHide { scheduleHide(after: Self.eventVisibilityDuration) }
    }

    private func openTask(_ task: CompletedTask) {
        guard phase != .launching, onOpen?(task) == true else { return }
        guard panel.isVisible, phase != .hidden else {
            onOpenFinished?(task)
            return
        }

        transitionID &+= 1
        let launchTransitionID = transitionID
        hideTimer?.invalidate()
        isPinned = false
        phase = .launching

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            phase = .hidden
            onOpenFinished?(task)
            return
        }

        rootView?.animateLaunch(selectedRow: rowsByEventID[task.eventID])
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.launchDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.launchDuration) { [weak self] in
            guard let self, self.transitionID == launchTransitionID else { return }
            self.panel.orderOut(nil)
            self.phase = .hidden
            self.pendingRebuild = false
            self.onOpenFinished?(task)
        }
    }

    private func rebuildContent(initiallyExpanded: Bool) {
        let screen = targetScreen ?? screenUnderPointer()
        let geometry = islandGeometry(for: screen)
        currentBodyInset = geometry.bodyInset
        currentNotchWidth = geometry.notchWidth
        currentNotchHeight = geometry.notchHeight

        let root = HUDContentView()
        root.bodyInset = geometry.bodyInset
        root.notchWidth = geometry.notchWidth
        root.notchHeight = geometry.notchHeight
        root.notchCenterOffset = geometry.notchCenterOffset

        let codexIcon = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Codex tasks ready"
        ) ?? NSImage())
        codexIcon.contentTintColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        codexIcon.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Codex")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = NSColor.white.withAlphaComponent(0.92)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let countText = tasks.isEmpty && updateVersion != nil
            ? "Update ready"
            : "\(tasks.count) completed"
        let count = NSTextField(labelWithString: countText)
        count.font = .systemFont(ofSize: 11, weight: .medium)
        count.textColor = NSColor.white.withAlphaComponent(0.56)
        count.translatesAutoresizingMaskIntoConstraints = false

        let toggleHint = NSTextField(labelWithString: "⌃⇧0")
        toggleHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        toggleHint.textColor = NSColor.white.withAlphaComponent(0.52)
        toggleHint.translatesAutoresizingMaskIntoConstraints = false

        let clear = ClosureButton { [weak self] in self?.onClear?() }
        clear.title = "Clear"
        clear.font = .systemFont(ofSize: 11, weight: .medium)
        clear.contentTintColor = NSColor.white.withAlphaComponent(0.66)
        clear.toolTip = "Dismiss all tasks"
        clear.alphaValue = 0
        clear.translatesAutoresizingMaskIntoConstraints = false
        let settings = ClosureButton { [weak self] in self?.onSettings?() }
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settings.contentTintColor = NSColor.white.withAlphaComponent(0.66)
        settings.toolTip = "Connection settings"
        settings.alphaValue = 0
        settings.translatesAutoresizingMaskIntoConstraints = false

        let update = ClosureButton { [weak self] in self?.onUpdate?() }
        update.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: "Install Codex Notch update"
        )
        update.contentTintColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        update.toolTip = updateVersion.map { "Install Codex Notch \($0)" }
        update.translatesAutoresizingMaskIntoConstraints = false
        update.isHidden = updateVersion == nil
        updateButton = update
        clear.isHidden = tasks.isEmpty
        root.controls = [clear, settings]

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        [codexIcon, heading, count, toggleHint, clear, update, settings].forEach(header.addSubview)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 36),
            codexIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 13),
            codexIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            codexIcon.widthAnchor.constraint(equalToConstant: 16),
            codexIcon.heightAnchor.constraint(equalToConstant: 16),
            heading.leadingAnchor.constraint(equalTo: codexIcon.trailingAnchor, constant: 8),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 8),
            count.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.leadingAnchor.constraint(greaterThanOrEqualTo: count.trailingAnchor, constant: 12),
            update.leadingAnchor.constraint(equalTo: clear.trailingAnchor, constant: 6),
            update.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            update.widthAnchor.constraint(equalToConstant: 24),
            update.heightAnchor.constraint(equalToConstant: 24),
            settings.leadingAnchor.constraint(equalTo: update.trailingAnchor, constant: 4),
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

        var rows: [TaskRowView] = []
        var rowLookup: [String: TaskRowView] = [:]
        for (index, task) in tasks.enumerated() {
            let row = TaskRowView(
                task: task,
                index: index,
                open: { [weak self] in self?.openTask(task) },
                dismiss: { [weak self] in self?.onDismiss?(index) }
            )
            rows.append(row)
            rowLookup[task.eventID] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        root.addSubview(stack)
        let contentTopInset = geometry.notchHeight + 18
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: geometry.bodyInset + 7
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -(geometry.bodyInset + 7)
            ),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: contentTopInset),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        root.onHoverChanged = { [weak self] hovering in
            if hovering { self?.hideTimer?.invalidate() }
            else if self?.isPinned == false {
                self?.scheduleHide(after: Self.eventVisibilityDuration)
            }
        }
        root.configureMotion(contentHost: stack, header: header, rows: rows)

        panel.contentView = root
        let height = geometry.notchHeight + 62 + CGFloat(tasks.count * 48)
        let size = NSSize(width: geometry.windowWidth, height: height)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.setContentSize(size)
        root.layoutSubtreeIfNeeded()
        root.setInitialState(expanded: initiallyExpanded)
        rootView = root
        rowsByEventID = rowLookup
        pendingRebuild = false
    }

    private func finishPendingRebuild(expanded: Bool) {
        guard pendingRebuild else { return }
        rebuildContent(initiallyExpanded: expanded)
        if expanded { positionPanel() }
    }

    private func positionPanel() {
        panel.setFrameOrigin(visibleOrigin())
    }

    private func visibleOrigin() -> NSPoint {
        let screen = targetScreen ?? screenUnderPointer()
        let frame = screen.frame
        return NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height
        )
    }

    private func islandGeometry(for screen: NSScreen) -> IslandGeometry {
        let menuHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let safeTop = screen.safeAreaInsets.top
        let notchHeight = max(CGFloat(28), max(safeTop, menuHeight))
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea
        var notchWidth: CGFloat = 128
        var centerOffset: CGFloat = 0
        if let leftArea, let rightArea {
            let measuredGap = rightArea.minX - leftArea.maxX
            let hasHardwareNotch = leftArea.width > 0
                && rightArea.width > 0
                && measuredGap >= 80
                && measuredGap <= screen.frame.width * 0.35
            if hasHardwareNotch {
                notchWidth = measuredGap
                centerOffset = (leftArea.maxX + rightArea.minX) / 2 - screen.frame.midX
            }
        }
        let bodyInset: CGFloat = 34
        let bodyWidth = min(680, max(500, screen.frame.width - 120))
        return IslandGeometry(
            windowWidth: bodyWidth + bodyInset * 2,
            bodyInset: bodyInset,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            notchCenterOffset: centerOffset
        )
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screenParametersDidChange() {
        let expanded = phase != .hidden && phase != .closing
        rebuildContent(initiallyExpanded: expanded)
        positionPanel()
    }

    private func scheduleHide(after interval: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}
