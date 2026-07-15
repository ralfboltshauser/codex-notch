import AppKit
import CoreGraphics
import QuartzCore

enum NotchMotion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static let ease = CAMediaTimingFunction(controlPoints: 0.25, 0.10, 0.25, 1)
    static let eventOpenDuration: TimeInterval = 0.24
    static let hoverOpenDuration: TimeInterval = 0.32
    static let closeDuration: TimeInterval = 0.17
    static let launchDuration: TimeInterval = 0.18
    static let pressInDuration: TimeInterval = 0.10
    static let pressOutDuration: TimeInterval = 0.14
    static let rowArrivalDuration: TimeInterval = 0.18
    static let rowDismissDuration: TimeInterval = 0.14
    static let reducedMotionFadeDuration: TimeInterval = 0.12
}

final class FocuslessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class ClosureButton: NSButton {
    var handler: (() -> Void)?
    private var pointerIsDown = false

    init(handler: (() -> Void)? = nil) {
        self.handler = handler
        super.init(frame: .zero)
        target = self
        action = #selector(pressed)
        isBordered = false
        refusesFirstResponder = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { handler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        setPointerDown(true)
        super.mouseDown(with: event)
        setPointerDown(false)
    }

    private func setPointerDown(_ isDown: Bool) {
        guard pointerIsDown != isDown, let layer else { return }
        pointerIsDown = isDown
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let target = isDown && !reduceMotion
            ? CATransform3DMakeScale(0.97, 0.97, 1)
            : CATransform3DIdentity
        let current = layer.presentation()?.transform ?? layer.transform
        let duration = isDown
            ? NotchMotion.pressInDuration
            : NotchMotion.pressOutDuration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()

        layer.removeAnimation(forKey: "buttonPress")
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = NotchMotion.easeOut
        layer.add(animation, forKey: "buttonPress")
    }
}

final class HUDContentView: NSView {
    private static let pitchBlack = CGColor(gray: 0, alpha: 1)
    private let backgroundGradient = CAGradientLayer()

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

    init(theme: NotchTheme) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.pitchBlack
        layer?.opacity = 1
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 1)
        backgroundGradient.colors = [
            theme.hudBottom.cgColor,
            theme.hudTop.cgColor,
            Self.pitchBlack,
        ]
        layer?.addSublayer(backgroundGradient)
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
        backgroundGradient.frame = bounds
        let blackBlendStart = max(0.62, 1 - (notchHeight + 18) / max(1, bounds.height))
        backgroundGradient.locations = [
            NSNumber(value: 0),
            NSNumber(value: blackBlendStart),
            NSNumber(value: 1),
        ]
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

    func prepareReducedMotionOpen() {
        setInitialState(expanded: true)
        guard let layer = contentHost?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    func animateReducedMotionContent(visible: Bool, duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: visible ? 1 : 0,
            transform: CATransform3DIdentity,
            duration: duration
        )
    }

    var hasContentAnimationForTesting: Bool {
        contentHost?.layer?.animation(forKey: "notchContent") != nil
    }

    var headerTopInsetForTesting: CGFloat? {
        guard let headerView else { return nil }
        layoutSubtreeIfNeeded()
        let frame = headerView.convert(headerView.bounds, to: self)
        return bounds.maxY - frame.maxY
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
        // Keep the mathematical edge outside the clipped layer. An edge exactly
        // at maxY gets anti-aliased into a one-pixel seam on bright desktops.
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
        let expandedRadius = min(CGFloat(28), (width - bodyInset * 2) / 4)
        let bottomRadius = interpolate(closedRadius, expandedRadius, progress)
        let bodyLeft = interpolate(neckLeft, bodyInset, progress)
        let bodyRight = interpolate(neckRight, width - bodyInset, progress)
        let bodyBottom = interpolate(neckBottom, 0, progress)
        let neckEdgeBottom = interpolate(neckBottom + closedRadius, neckBottom + 4, progress)
        let topLeft = interpolate(neckLeft, 0, progress)
        let topRight = interpolate(neckRight, width, progress)
        let shoulderStartY = interpolate(neckEdgeBottom, top, progress)
        let shoulderBottom = interpolate(
            neckBottom + closedRadius,
            max(32, height - notchHeight),
            progress
        )
        let expandedShoulderControlY = height - notchHeight * 0.46
        let shoulderControlY = interpolate(
            shoulderBottom,
            expandedShoulderControlY,
            progress
        )

        // Expanded, the whole top edge is black and clipped by the display
        // boundary. The body narrows through the shoulders like one oversized
        // notch. The extra zero-length lines preserve path compatibility with
        // the compact hardware-notch shape during interruptible animation.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: topLeft, y: top))
        path.addLine(to: CGPoint(x: topRight, y: top))
        path.addLine(to: CGPoint(x: topRight, y: shoulderStartY))
        path.addCurve(
            to: CGPoint(x: bodyRight, y: shoulderBottom),
            control1: CGPoint(
                x: interpolate(neckRight, width - bodyInset * 0.52, progress),
                y: shoulderStartY
            ),
            control2: CGPoint(
                x: bodyRight,
                y: shoulderControlY
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
            to: CGPoint(x: topLeft, y: shoulderStartY),
            control1: CGPoint(
                x: bodyLeft,
                y: shoulderControlY
            ),
            control2: CGPoint(
                x: interpolate(neckLeft, bodyInset * 0.52, progress),
                y: shoulderStartY
            )
        )
        path.addLine(to: CGPoint(x: topLeft, y: top))
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
            context.timingFunction = NotchMotion.ease
            controls.forEach { $0.animator().alphaValue = 1 }
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = NotchMotion.ease
            controls.forEach { $0.animator().alphaValue = 0 }
        }
    }
}

final class NumberBadgeView: NSView {
    private let numberText: String
    private let shortcutText: String?
    private let label: NSTextField

    init(number: Int, shortcut: String?, theme: NotchTheme) {
        numberText = "\(number)"
        shortcutText = shortcut
        label = NSTextField(labelWithString: numberText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.accent.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = theme.primaryText
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

    func showShortcut(_ visible: Bool) {
        label.stringValue = visible ? (shortcutText ?? numberText) : numberText
    }

    var textForTesting: String { label.stringValue }
}

final class EmptyStateView: NSView {
    init(updateVersion: String?, theme: NotchTheme) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconWell = NSView()
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.backgroundColor = theme.surface.cgColor
        iconWell.layer?.borderColor = theme.border.cgColor
        iconWell.layer?.borderWidth = 1
        iconWell.layer?.cornerRadius = 18
        iconWell.layer?.cornerCurve = .continuous

        let symbolName = updateVersion == nil ? "checkmark" : "arrow.down"
        let symbolDescription = updateVersion == nil ? "No completed tasks" : "Update ready"
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: symbolDescription
        ) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(icon)

        let title = NSTextField(labelWithString: updateVersion == nil ? "All clear" : "Update ready")
        title.font = theme.font(ofSize: 13, weight: .medium)
        title.textColor = theme.primaryText
        title.alignment = .center

        let detailText = updateVersion.map { "Codex Notch \($0) is ready to install." }
            ?? "Completed Codex tasks will appear here."
        let detail = NSTextField(labelWithString: detailText)
        detail.font = theme.font(ofSize: 11.5, weight: .regular)
        detail.textColor = theme.secondaryText
        detail.alignment = .center

        let settingsHint = NSTextField(labelWithString: "⌘,  Settings")
        settingsHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        settingsHint.textColor = theme.tertiaryText
        settingsHint.alignment = .center

        let stack = NSStackView(views: [iconWell, title, detail, settingsHint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(8, after: iconWell)
        stack.setCustomSpacing(9, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 104),
            iconWell.widthAnchor.constraint(equalToConstant: 36),
            iconWell.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class RemoteHostStatusBadgeView: NSView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.62)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ snapshot: RemoteHostHealthSnapshot) {
        label.stringValue = snapshot.summaryText
        let color: NSColor
        if snapshot.problemCount > 0 {
            color = snapshot.workingCount > 0 ? .systemOrange : .systemRed
        } else if snapshot.checkingCount > 0 {
            color = NSColor.white.withAlphaComponent(0.42)
        } else {
            color = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        }
        dot.layer?.backgroundColor = color.cgColor
        toolTip = snapshot.hosts.map { host in
            let health = snapshot.health(for: host)
            if let detail = health.detailText {
                return "\(host.label): \(health.statusText) — \(detail)"
            }
            return "\(host.label): \(health.statusText)"
        }.joined(separator: "\n")
        setAccessibilityLabel("Remote hosts: \(snapshot.summaryText)")
    }
}

final class TaskRowView: NSView {
    let task: CompletedTask

    private let openHandler: () -> Void
    private let shouldReduceMotion: () -> Bool
    private let dismissButton: ClosureButton
    private let numberBadge: NumberBadgeView
    private let theme: NotchTheme
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isTrackingPress = false
    private var isPressed = false
    private var isDismissing = false

    init(
        task: CompletedTask,
        index: Int,
        theme: NotchTheme,
        shouldReduceMotion: @escaping () -> Bool,
        open: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.task = task
        self.theme = theme
        self.shouldReduceMotion = shouldReduceMotion
        openHandler = open
        dismissButton = ClosureButton(handler: dismiss)
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

        let title = NSTextField(labelWithString: task.title)
        title.font = theme.font(ofSize: 14, weight: .medium)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let source = NSTextField(labelWithString: task.sourceLabel)
        source.font = theme.font(ofSize: 10.5, weight: .medium)
        source.textColor = theme.secondaryText
        source.lineBreakMode = .byTruncatingTail
        source.translatesAutoresizingMaskIntoConstraints = false
        source.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let shortcut = NSTextField(
            labelWithString: GlobalHotKeys.openShortcutLabel(at: index) ?? ""
        )
        shortcut.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcut.textColor = theme.secondaryText
        shortcut.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss task")
        dismissButton.contentTintColor = theme.secondaryText
        dismissButton.toolTip = GlobalHotKeys.dismissShortcutLabel(at: index)
            .map { "Dismiss — \($0)" } ?? "Dismiss"
        dismissButton.alphaValue = 0
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        [numberBadge, title, source, shortcut, dismissButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            numberBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            numberBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: numberBadge.trailingAnchor, constant: 11),
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

    func setShortcutLetterVisible(_ visible: Bool) {
        numberBadge.showShortcut(visible)
    }

    var badgeTextForTesting: String { numberBadge.textForTesting }

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
        updateAppearance(
            duration: pressed ? NotchMotion.pressInDuration : NotchMotion.pressOutDuration,
            timingFunction: NotchMotion.easeOut
        )
    }

    private func updateAppearance(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard let layer else { return }
        let targetBackground = (
            isPressed ? theme.pressedSurface : (isHovered ? theme.hoverSurface : NSColor.clear)
        ).cgColor
        let targetTransform = isPressed && !shouldReduceMotion()
            ? CATransform3DMakeScale(0.98, 0.98, 1)
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
        group.timingFunction = timingFunction
        layer.add(group, forKey: "rowPress")
    }

    func animateArrival(reducedMotion: Bool, delay: TimeInterval = 0) {
        guard let layer else { return }
        let initialTransform = reducedMotion
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, 5, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.removeAnimation(forKey: "rowArrival")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = initialTransform
        transform.toValue = CATransform3DIdentity
        let group = CAAnimationGroup()
        group.animations = [opacity, transform]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = reducedMotion
            ? NotchMotion.reducedMotionFadeDuration
            : NotchMotion.rowArrivalDuration
        group.fillMode = .backwards
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "rowArrival")
    }

    func animateReposition(from oldFrame: NSRect, to newFrame: NSRect) {
        guard let layer else { return }
        let deltaX = oldFrame.midX - newFrame.midX
        let deltaY = oldFrame.midY - newFrame.midY
        guard abs(deltaX) > 0.5 || abs(deltaY) > 0.5 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.removeAnimation(forKey: "rowReflow")
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeTranslation(deltaX, deltaY, 0)
        animation.toValue = CATransform3DIdentity
        animation.duration = NotchMotion.rowArrivalDuration
        animation.timingFunction = NotchMotion.easeOut
        layer.add(animation, forKey: "rowReflow")
    }

    func animateDismiss(delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
        guard !isDismissing, let layer else {
            completion?()
            return
        }
        isDismissing = true
        isTrackingPress = false
        isPressed = false
        dismissButton.isEnabled = false
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let targetTransform = CATransform3DMakeTranslation(14, 0, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = targetTransform
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
        group.duration = NotchMotion.rowDismissDuration
        group.fillMode = .backwards
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "rowDismiss")

        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay + NotchMotion.rowDismissDuration
        ) {
            completion?()
        }
    }

    func holdInvisibleForPendingDismissal() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
    }

    var hasArrivalAnimationForTesting: Bool {
        layer?.animation(forKey: "rowArrival") != nil
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
            layer.backgroundColor = theme.pressedSurface.cgColor
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
        updateAppearance(duration: 0.10, timingFunction: NotchMotion.ease)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = NotchMotion.ease
            dismissButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isPressed { updateAppearance(duration: 0.12, timingFunction: NotchMotion.ease) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = NotchMotion.ease
            dismissButton.animator().alphaValue = 0
        }
    }
}

final class UsageProgressView: NSView {
    private let remainingFraction: CGFloat
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    init(remainingPercent: Int, theme: NotchTheme) {
        remainingFraction = CGFloat(min(100, max(0, remainingPercent))) / 100
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        trackLayer.backgroundColor = theme.primaryText.withAlphaComponent(0.10).cgColor
        fillLayer.backgroundColor = theme.accent.cgColor
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        fillLayer.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width * remainingFraction,
            height: bounds.height
        )
        fillLayer.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }
}

final class WeeklyLimitView: NSView {
    let percentageTextForTesting: String
    let resetTextForTesting: String
    let forecastTextForTesting: String
    let trendTextForTesting: String?

    init(overview: CodexUsageOverview, theme: NotchTheme, now: Date = Date()) {
        let limit = overview.limit
        percentageTextForTesting = "\(limit.remainingPercent)% left"
        if let resetsAt = limit.resetsAt {
            resetTextForTesting = "Resets \(Self.shortDate(resetsAt))"
        } else {
            resetTextForTesting = "Reset time unavailable"
        }
        switch overview.forecast {
        case .depleted:
            forecastTextForTesting = "Weekly limit reached"
        case .learning:
            forecastTextForTesting = "Learning your pace"
        case .quiet:
            forecastTextForTesting = "No recent usage change"
        case .lastsThroughReset:
            forecastTextForTesting = "At this pace · lasts through reset"
        case .nearReset:
            forecastTextForTesting = "At this pace · close to reset"
        case .exhausts(let estimatedAt, _):
            forecastTextForTesting = "At this pace · \(Self.timeRemaining(until: estimatedAt, now: now))"
        }
        if let trend = overview.recentTrend {
            let hours = min(24, max(1, Int((trend.observedFor / 3_600).rounded())))
            trendTextForTesting = "\(trend.usedPercent)% used · \(hours)h"
        } else {
            trendTextForTesting = nil
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = theme.quietSurface.cgColor
        layer?.borderColor = theme.border.cgColor
        layer?.borderWidth = 1

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis",
            accessibilityDescription: "Weekly Codex limit"
        ) ?? NSImage())
        icon.contentTintColor = theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Weekly usage")
        title.font = theme.font(ofSize: 11, weight: .medium)
        title.textColor = theme.secondaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let trend = NSTextField(labelWithString: trendTextForTesting ?? "")
        trend.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        trend.textColor = theme.tertiaryText
        trend.alignment = .right
        trend.isHidden = trendTextForTesting == nil
        trend.translatesAutoresizingMaskIntoConstraints = false

        let progress = UsageProgressView(
            remainingPercent: limit.remainingPercent,
            theme: theme
        )

        let percentage = NSTextField(labelWithString: percentageTextForTesting)
        percentage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentage.textColor = theme.primaryText
        percentage.alignment = .right
        percentage.translatesAutoresizingMaskIntoConstraints = false

        let forecast = NSTextField(labelWithString: forecastTextForTesting)
        forecast.font = theme.font(ofSize: 10.5, weight: .medium)
        forecast.textColor = Self.forecastColor(overview.forecast, theme: theme)
        forecast.lineBreakMode = .byTruncatingTail
        forecast.translatesAutoresizingMaskIntoConstraints = false
        forecast.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let reset = NSTextField(labelWithString: resetTextForTesting)
        reset.font = theme.font(ofSize: 10.5, weight: .regular)
        reset.textColor = theme.tertiaryText
        reset.alignment = .right
        reset.translatesAutoresizingMaskIntoConstraints = false
        reset.setContentCompressionResistancePriority(.required, for: .horizontal)

        [icon, title, trend, percentage, progress, forecast, reset].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 64),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            trend.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
            trend.trailingAnchor.constraint(equalTo: percentage.leadingAnchor, constant: -12),
            trend.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            percentage.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            percentage.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            progress.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            progress.heightAnchor.constraint(equalToConstant: 5),
            forecast.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            forecast.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            reset.leadingAnchor.constraint(greaterThanOrEqualTo: forecast.trailingAnchor, constant: 10),
            reset.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            reset.centerYAnchor.constraint(equalTo: forecast.centerYAnchor),
        ])

        let paceDescription: String
        switch overview.forecast {
        case .lastsThroughReset(let pace), .nearReset(let pace), .exhausts(_, let pace):
            paceDescription = String(format: " About %.1f%% per day.", pace)
        default:
            paceDescription = ""
        }
        let trendDescription = overview.recentTrend.map {
            let hours = max(1, Int(($0.observedFor / 3_600).rounded()))
            return " Based on a \($0.usedPercent)% change over \(hours) hours."
        } ?? ""
        toolTip = "\(forecastTextForTesting).\(paceDescription)\(trendDescription) "
            + "Local checks run every 15 minutes; Codex reports whole percentages."
        setAccessibilityElement(true)
        setAccessibilityLabel("Codex weekly usage")
        setAccessibilityValue(
            "\(percentageTextForTesting), \(forecastTextForTesting), \(resetTextForTesting)"
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return formatter.string(from: date)
    }

    private static func timeRemaining(until date: Date, now: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        if remaining < 45 * 60 { return "<1h left" }
        if remaining < 48 * 60 * 60 {
            return "~\(max(1, Int((remaining / 3_600).rounded())))h left"
        }
        return "~\(max(2, Int((remaining / 86_400).rounded())))d left"
    }

    private static func forecastColor(
        _ forecast: CodexUsageForecast,
        theme: NotchTheme
    ) -> NSColor {
        switch forecast {
        case .depleted: return .systemOrange
        case .exhausts: return .systemOrange
        case .lastsThroughReset: return theme.accent
        case .learning, .quiet, .nearReset: return theme.secondaryText
        }
    }
}

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
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
}

private struct IslandGeometry {
    let windowWidth: CGFloat
    let bodyInset: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchCenterOffset: CGFloat
    let hasHardwareNotch: Bool
}

final class OverlayController {
    static let eventVisibilityDuration: TimeInterval = 5
    private static let menuBarHeaderHeight: CGFloat = 36
    private static let reclaimedTopPadding: CGFloat = 18
    private static let hardwareNotchPadding: CGFloat = 10

    private enum Phase {
        case hidden
        case opening
        case open
        case closing
        case launching
    }

    private let panel: FocuslessPanel
    private let shouldReduceMotion: () -> Bool
    private let shortcutModifierState: () -> Bool
    private let automaticOpenAllowed: () -> Bool
    private var tasks: [CompletedTask] = []
    private var activeTasks: [ActiveTask] = []
    private var showsActiveTasks = ActiveTaskPreferences.shared.isVisible
    private var hideTimer: Timer?
    private var shortcutModifierTimer: Timer?
    private var shortcutLettersVisible = false
    private var lockedActiveTasks: [ActiveTask]?
    private var lockedCompletedTasks: [CompletedTask]?
    private var eventAutoCloseCanBeCancelled = false
    private var targetScreen: NSScreen?
    private var isPinned = false
    private var isThemePreviewActive = false
    private var currentBodyInset: CGFloat = 0
    private var currentNotchWidth: CGFloat = 0
    private var currentNotchHeight: CGFloat = 0
    private var transitionID = 0
    private var phase: Phase = .hidden
    private var pendingRebuild = false
    private var updateVersion: String?
    private var usageOverview: CodexUsageOverview?
    private var remoteHealth = RemoteHostHealthSnapshot.empty
    private weak var updateButton: ClosureButton?
    private weak var settingsButton: ClosureButton?
    private weak var remoteStatusBadge: RemoteHostStatusBadgeView?
    private weak var emptyStateView: EmptyStateView?
    private weak var weeklyLimitView: WeeklyLimitView?
    private weak var shortcutLockLabel: NSTextField?
    private weak var rootView: HUDContentView?
    private var rowsByEventID: [String: TaskRowView] = [:]
    private var activeTaskRows: [ActiveTaskRowView] = []
    private var dismissingEventIDs: Set<String> = []
    private var themeObserver: NSObjectProtocol?

    var onOpen: ((CompletedTask) -> Bool)?
    var onOpenActive: ((ActiveTask) -> Bool)?
    var onOpenFinished: ((CompletedTask) -> Void)?
    var onDismiss: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: (() -> Void)?
    var onToggleActiveTasks: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    var frameForTesting: NSRect { panel.frame }
    var bodyHeightForTesting: CGFloat { panel.frame.height }
    var bodyWidthForTesting: CGFloat { panel.frame.width - currentBodyInset * 2 }
    var notchWidthForTesting: CGFloat { currentNotchWidth }
    var notchHeightForTesting: CGFloat { currentNotchHeight }
    var eventVisibilityDurationForTesting: TimeInterval { Self.eventVisibilityDuration }
    var hoverOpenDurationForTesting: TimeInterval { NotchMotion.hoverOpenDuration }
    var isPinnedForTesting: Bool { isPinned }
    var isThemePreviewActiveForTesting: Bool { isThemePreviewActive }
    var hasHideTimerForTesting: Bool { hideTimer?.isValid == true }
    var isVisibleForTesting: Bool { panel.isVisible }
    var isLaunchingForTesting: Bool { phase == .launching }
    var panelAlphaForTesting: CGFloat { panel.alphaValue }
    var contentViewForTesting: NSView? { panel.contentView }
    var isUpdateAvailableForTesting: Bool { updateVersion != nil }
    var updateButtonForTesting: NSButton? { updateButton }
    var settingsButtonForTesting: NSButton? { settingsButton }
    var remoteStatusTextForTesting: String? {
        remoteHealth.hosts.isEmpty ? nil : remoteHealth.summaryText
    }
    var hasEmptyStateForTesting: Bool { emptyStateView != nil }
    var weeklyLimitViewForTesting: WeeklyLimitView? { weeklyLimitView }
    var isShortcutOrderLockedForTesting: Bool { shortcutLettersVisible }
    var shortcutLockTextForTesting: String? { shortcutLockLabel?.stringValue }
    var shortcutTaskTitlesForTesting: [String] {
        shortcutActiveTasks.map(\.title) + shortcutCompletedTasks.map(\.title)
    }
    var taskBadgeTextsForTesting: [String] {
        activeTaskRows.map(\.badgeTextForTesting)
            + presentedTasks.compactMap { rowsByEventID[$0.eventID]?.badgeTextForTesting }
    }
    var rowArrivalAnimationCountForTesting: Int {
        rowsByEventID.values.filter(\.hasArrivalAnimationForTesting).count
    }
    var hasContentAnimationForTesting: Bool {
        rootView?.hasContentAnimationForTesting == true
    }
    var headerTopInsetForTesting: CGFloat? { rootView?.headerTopInsetForTesting }
    static func menuBarNotchExclusionForTesting(
        notchWidth: CGFloat,
        centerOffset: CGFloat,
        hasHardwareNotch: Bool
    ) -> ClosedRange<CGFloat>? {
        menuBarNotchExclusion(
            notchWidth: notchWidth,
            centerOffset: centerOffset,
            hasHardwareNotch: hasHardwareNotch
        )
    }
    var hasContent: Bool {
        !tasks.isEmpty
            || (showsActiveTasks && !activeTasks.isEmpty)
            || updateVersion != nil
            || usageOverview != nil
    }
    private var presentedTasks: [CompletedTask] {
        guard showsActiveTasks, !activeTasks.isEmpty else { return tasks }
        let activeKeys = Set(activeTasks.map { "\($0.sourceID)\u{0}\($0.threadID.lowercased())" })
        return tasks.filter { !activeKeys.contains("\($0.sourceID)\u{0}\($0.threadID.lowercased())") }
    }
    private var displayedActiveTasks: [ActiveTask] {
        showsActiveTasks ? Array(activeTasks.prefix(4)) : []
    }
    private var shortcutActiveTasks: [ActiveTask] {
        lockedActiveTasks ?? displayedActiveTasks
    }
    private var shortcutCompletedTasks: [CompletedTask] {
        lockedCompletedTasks ?? presentedTasks
    }

    init(
        automaticOpenAllowed: @escaping () -> Bool = { true },
        shouldReduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        shortcutModifierState: @escaping () -> Bool = {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            return flags.contains(.maskControl) && flags.contains(.maskShift)
        }
    ) {
        self.automaticOpenAllowed = automaticOpenAllowed
        self.shouldReduceMotion = shouldReduceMotion
        self.shortcutModifierState = shortcutModifierState
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
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.themeDidChange() }
    }

    deinit {
        shortcutModifierTimer?.invalidate()
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    func refreshShortcutModifierStateForTesting() {
        refreshShortcutModifierState()
    }

    private func themeDidChange() {
        if deferVisibleRebuildWhileShortcutsLocked() { return }
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

    func update(tasks: [CompletedTask]) {
        let previousEventIDs = Set(self.tasks.map(\.eventID))
        let previousRowFrames = rowsByEventID.mapValues(screenFrame)
        let insertedEventIDs = tasks
            .map(\.eventID)
            .filter { !previousEventIDs.contains($0) }
        self.tasks = tasks
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
            if !shouldReduceMotion() {
                for (eventID, oldFrame) in previousRowFrames {
                    guard let row = rowsByEventID[eventID] else { continue }
                    row.animateReposition(from: oldFrame, to: screenFrame(row))
                }
            }
            for (index, eventID) in insertedEventIDs.enumerated() {
                rowsByEventID[eventID]?.animateArrival(
                    reducedMotion: shouldReduceMotion(),
                    delay: min(Double(index) * 0.03, 0.09)
                )
            }
        }
    }

    func update(activeTasks: [ActiveTask], visible: Bool) {
        self.activeTasks = activeTasks
        showsActiveTasks = visible
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching: pendingRebuild = true
        case .hidden: rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func setUpdateAvailable(version: String?) {
        let wasAvailable = updateVersion != nil
        updateVersion = version
        if deferVisibleRebuildWhileShortcutsLocked() { return }
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

    func setUsageOverview(_ overview: CodexUsageOverview?) {
        guard usageOverview != overview else { return }
        usageOverview = overview
        if deferVisibleRebuildWhileShortcutsLocked() { return }
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

    func setRemoteHostHealth(_ snapshot: RemoteHostHealthSnapshot) {
        let previousIDs = remoteHealth.hosts.map(\.id)
        remoteHealth = snapshot
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        guard previousIDs != snapshot.hosts.map(\.id) else {
            remoteStatusBadge?.update(snapshot)
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

    func showForEvent() {
        guard automaticOpenAllowed(), hasContent else { return }
        if !isPinned { eventAutoCloseCanBeCancelled = true }
        if shortcutLettersVisible, panel.isVisible {
            makeEventPresentationPersistent()
            return
        }
        if phase == .hidden { targetScreen = screenUnderPointer() }
        if phase == .open || phase == .opening {
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }
        present(autoHide: !isPinned, duration: NotchMotion.eventOpenDuration)
    }

    func showFromNotchHover(on screen: NSScreen) {
        guard !isThemePreviewActive, phase != .launching else { return }
        guard phase != .open, phase != .opening else { return }
        targetScreen = screen
        isPinned = false
        eventAutoCloseCanBeCancelled = false
        if phase == .hidden { rebuildContent(initiallyExpanded: false) }
        present(autoHide: true, duration: NotchMotion.hoverOpenDuration)
    }

    func setThemePreviewVisible(_ visible: Bool, on screen: NSScreen? = nil) {
        guard isThemePreviewActive != visible else { return }
        isThemePreviewActive = visible
        eventAutoCloseCanBeCancelled = false
        if visible {
            targetScreen = screen ?? screenUnderPointer()
            isPinned = true
            present(autoHide: false, duration: 0)
        } else {
            hide(immediately: true)
        }
    }

    func toggle() {
        guard !isThemePreviewActive else { return }
        switch phase {
        case .hidden:
            targetScreen = screenUnderPointer()
            isPinned = true
            eventAutoCloseCanBeCancelled = false
            present(autoHide: false, duration: 0)
        case .closing:
            isPinned = true
            eventAutoCloseCanBeCancelled = false
            present(autoHide: false, duration: 0)
        case .launching:
            break
        case .opening, .open:
            hide(immediately: true)
        }
    }

    func openSettings() {
        guard panel.isVisible else { return }
        if isThemePreviewActive {
            onSettings?()
            return
        }
        hide(immediately: true)
        onSettings?()
    }

    func openTask(at index: Int, animated: Bool = true) {
        let active = shortcutActiveTasks
        if active.indices.contains(index) {
            openActiveTask(active[index])
            return
        }
        let completedIndex = index - active.count
        let completed = shortcutCompletedTasks
        guard completed.indices.contains(completedIndex) else { return }
        openTask(completed[completedIndex], animated: animated)
    }

    func dismissTask(at index: Int, animated: Bool = true) {
        let completedIndex = index - shortcutActiveTasks.count
        let visibleTasks = shortcutCompletedTasks
        guard visibleTasks.indices.contains(completedIndex) else { return }
        let eventID = visibleTasks[completedIndex].eventID
        guard animated,
              !shouldReduceMotion(),
              phase == .open,
              let row = rowsByEventID[eventID]
        else {
            guard let storedIndex = tasks.firstIndex(where: { $0.eventID == eventID }) else { return }
            onDismiss?(storedIndex)
            return
        }
        dismissingEventIDs.insert(eventID)
        row.animateDismiss { [weak self] in
            guard let self else { return }
            self.dismissingEventIDs.remove(eventID)
            guard let currentIndex = self.tasks.firstIndex(where: { $0.eventID == eventID })
            else { return }
            self.onDismiss?(currentIndex)
        }
    }

    func clearTasks(animated: Bool = true) {
        let rows = tasks.compactMap { rowsByEventID[$0.eventID] }
        guard animated, !shouldReduceMotion(), phase == .open, !rows.isEmpty else {
            onClear?()
            return
        }
        dismissingEventIDs.formUnion(tasks.map(\.eventID))
        for (index, row) in rows.enumerated() {
            let delay = min(Double(index) * 0.012, 0.10)
            let completion: (() -> Void)? = index == rows.count - 1
                ? { [weak self] in
                    self?.dismissingEventIDs.removeAll()
                    self?.onClear?()
                }
                : nil
            row.animateDismiss(delay: delay, completion: completion)
        }
    }

    func hide(immediately: Bool = false) {
        hideTimer?.invalidate()
        isPinned = false
        eventAutoCloseCanBeCancelled = false
        transitionID &+= 1
        let hidingTransitionID = transitionID
        guard phase != .hidden || panel.isVisible else { return }

        if immediately {
            rootView?.setInitialState(expanded: false)
            orderPanelOut()
            phase = .hidden
            finishPendingRebuild(expanded: false)
            return
        }
        guard phase != .launching else { return }

        phase = .closing
        if shouldReduceMotion() {
            rootView?.animateReducedMotionContent(
                visible: false,
                duration: NotchMotion.reducedMotionFadeDuration
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NotchMotion.reducedMotionFadeDuration
            ) { [weak self] in
                guard let self, self.transitionID == hidingTransitionID else { return }
                self.orderPanelOut()
                self.phase = .hidden
                self.rootView?.setInitialState(expanded: false)
                self.finishPendingRebuild(expanded: false)
            }
            return
        }

        rootView?.animateContentOut(duration: 0.10)
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.closeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.closeDuration) { [weak self] in
            guard let self, self.transitionID == hidingTransitionID else { return }
            self.orderPanelOut()
            self.phase = .hidden
            self.finishPendingRebuild(expanded: false)
        }
    }

    private func present(autoHide: Bool, duration: TimeInterval) {
        if phase == .open || phase == .opening {
            if autoHide, !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }

        transitionID &+= 1
        let presentingTransitionID = transitionID
        let wasHidden = phase == .hidden || !panel.isVisible
        if rootView == nil { rebuildContent(initiallyExpanded: false) }
        positionPanel()
        hideTimer?.invalidate()
        panel.alphaValue = 1
        let reduceMotion = shouldReduceMotion()
        let shouldAnimateSpatially = duration > 0 && !reduceMotion
        let shouldFade = duration > 0 && reduceMotion
        if wasHidden && shouldFade { rootView?.prepareReducedMotionOpen() }
        if wasHidden { orderPanelFront() }

        phase = .opening
        if shouldAnimateSpatially {
            rootView?.animateExpansion(expanded: true, duration: duration)
            rootView?.animateContentIn(duration: min(0.16, duration))
        } else if shouldFade {
            rootView?.animateReducedMotionContent(
                visible: true,
                duration: NotchMotion.reducedMotionFadeDuration
            )
        } else {
            rootView?.setInitialState(expanded: true)
            phase = .open
            finishPendingRebuild(expanded: true)
        }

        if shouldAnimateSpatially || shouldFade {
            let completionDuration = shouldAnimateSpatially
                ? duration
                : NotchMotion.reducedMotionFadeDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + completionDuration) { [weak self] in
                guard let self, self.transitionID == presentingTransitionID else { return }
                self.phase = .open
                self.finishPendingRebuild(expanded: true)
            }
        }
        if autoHide, !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
    }

    private func openTask(_ task: CompletedTask, animated: Bool = true) {
        guard phase != .launching, onOpen?(task) == true else { return }
        guard animated, phase != .hidden, !shouldReduceMotion() else {
            transitionID &+= 1
            hideTimer?.invalidate()
            isPinned = false
            if panel.isVisible { orderPanelOut() }
            phase = .hidden
            pendingRebuild = false
            onOpenFinished?(task)
            return
        }

        transitionID &+= 1
        let launchTransitionID = transitionID
        hideTimer?.invalidate()
        isPinned = false
        phase = .launching

        rootView?.animateLaunch(selectedRow: rowsByEventID[task.eventID])
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.launchDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.launchDuration) { [weak self] in
            guard let self, self.transitionID == launchTransitionID else { return }
            self.orderPanelOut()
            self.phase = .hidden
            self.pendingRebuild = false
            self.onOpenFinished?(task)
        }
    }

    private func openActiveTask(_ task: ActiveTask) {
        guard onOpenActive?(task) == true else { return }
        hide(immediately: shouldReduceMotion())
    }

    private func rebuildContent(initiallyExpanded: Bool) {
        let theme = ThemeStore.shared.activeTheme
        let screen = targetScreen ?? screenUnderPointer()
        let geometry = islandGeometry(for: screen)
        currentBodyInset = geometry.bodyInset
        currentNotchWidth = geometry.notchWidth
        currentNotchHeight = geometry.notchHeight

        let root = HUDContentView(theme: theme)
        root.bodyInset = geometry.bodyInset
        root.notchWidth = geometry.notchWidth
        root.notchHeight = geometry.notchHeight
        root.notchCenterOffset = geometry.notchCenterOffset

        let codexIcon = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Codex tasks ready"
        ) ?? NSImage())
        codexIcon.contentTintColor = theme.accent
        codexIcon.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Codex")
        heading.font = theme.font(ofSize: 13, weight: .semibold)
        heading.textColor = theme.primaryText
        heading.translatesAutoresizingMaskIntoConstraints = false

        let visibleActiveCount = showsActiveTasks ? activeTasks.count : 0
        let completedTasks = presentedTasks
        let countText: String
        if completedTasks.isEmpty && visibleActiveCount == 0 {
            countText = updateVersion == nil ? "Nothing waiting" : "Update ready"
        } else if visibleActiveCount > 0 && !completedTasks.isEmpty {
            countText = "\(visibleActiveCount) active · \(completedTasks.count) completed"
        } else if visibleActiveCount > 0 {
            countText = "\(visibleActiveCount) active"
        } else {
            countText = "\(completedTasks.count) completed"
        }
        let count = NSTextField(labelWithString: countText)
        count.font = theme.font(ofSize: 11, weight: .medium)
        count.textColor = theme.secondaryText
        count.translatesAutoresizingMaskIntoConstraints = false

        let toggleHint = NSTextField(labelWithString: GlobalHotKeys.toggleShortcutLabel())
        toggleHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        toggleHint.alignment = .center
        toggleHint.wantsLayer = true
        toggleHint.layer?.cornerRadius = 6
        toggleHint.translatesAutoresizingMaskIntoConstraints = false
        updateShortcutLockLabel(toggleHint, locked: shortcutLettersVisible, theme: theme)
        shortcutLockLabel = toggleHint

        let activeToggle = ClosureButton { [weak self] in self?.onToggleActiveTasks?() }
        activeToggle.image = NSImage(
            systemSymbolName: showsActiveTasks ? "bolt.fill" : "bolt.slash",
            accessibilityDescription: showsActiveTasks ? "Hide active tasks" : "Show active tasks"
        )
        activeToggle.contentTintColor = showsActiveTasks ? theme.accent : theme.secondaryText
        activeToggle.title = GlobalHotKeys.activeTasksShortcutLabel()
        activeToggle.imagePosition = .imageLeading
        activeToggle.imageHugsTitle = true
        activeToggle.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        activeToggle.toolTip = "\(showsActiveTasks ? "Hide" : "Show") active tasks — \(GlobalHotKeys.activeTasksShortcutLabel())"
        activeToggle.translatesAutoresizingMaskIntoConstraints = false

        let clear = ClosureButton { [weak self] in self?.clearTasks() }
        clear.title = "Clear"
        clear.font = theme.font(ofSize: 11, weight: .medium)
        clear.contentTintColor = theme.secondaryText
        clear.toolTip = "Dismiss all tasks"
        clear.alphaValue = 0
        clear.translatesAutoresizingMaskIntoConstraints = false
        let settings = ClosureButton { [weak self] in
            self?.openSettings()
        }
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settings.contentTintColor = theme.secondaryText
        settings.toolTip = "Appearance and connections"
        settings.alphaValue = 0
        settings.translatesAutoresizingMaskIntoConstraints = false
        settingsButton = settings

        let update = ClosureButton { [weak self] in self?.onUpdate?() }
        update.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: "Install Codex Notch update"
        )
        update.contentTintColor = theme.accent
        update.toolTip = updateVersion.map { "Install Codex Notch \($0)" }
        update.translatesAutoresizingMaskIntoConstraints = false
        update.isHidden = updateVersion == nil
        updateButton = update
        clear.isHidden = completedTasks.isEmpty
        root.controls = [clear, settings]

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        var headerViews: [NSView] = [codexIcon, heading, count]
        let statusBadge: RemoteHostStatusBadgeView?
        if remoteHealth.hosts.isEmpty {
            statusBadge = nil
            remoteStatusBadge = nil
        } else {
            let badge = RemoteHostStatusBadgeView()
            badge.update(remoteHealth)
            statusBadge = badge
            remoteStatusBadge = badge
            headerViews.append(badge)
        }
        headerViews.append(contentsOf: [toggleHint, activeToggle, clear, update, settings])
        headerViews.forEach(header.addSubview)
        var headerConstraints = [
            header.heightAnchor.constraint(equalToConstant: Self.menuBarHeaderHeight),
            codexIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 13),
            codexIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            codexIcon.widthAnchor.constraint(equalToConstant: 16),
            codexIcon.heightAnchor.constraint(equalToConstant: 16),
            heading.leadingAnchor.constraint(equalTo: codexIcon.trailingAnchor, constant: 8),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 8),
            count.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            update.leadingAnchor.constraint(equalTo: clear.trailingAnchor, constant: 6),
            update.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            update.widthAnchor.constraint(equalToConstant: 24),
            update.heightAnchor.constraint(equalToConstant: 24),
            activeToggle.leadingAnchor.constraint(equalTo: settings.trailingAnchor, constant: 4),
            activeToggle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            activeToggle.widthAnchor.constraint(equalToConstant: 65),
            activeToggle.heightAnchor.constraint(equalToConstant: 24),
            settings.leadingAnchor.constraint(equalTo: update.trailingAnchor, constant: 4),
            toggleHint.leadingAnchor.constraint(equalTo: activeToggle.trailingAnchor, constant: 8),
            toggleHint.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            toggleHint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            toggleHint.widthAnchor.constraint(equalToConstant: 56),
            toggleHint.heightAnchor.constraint(equalToConstant: 20),
            settings.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            settings.widthAnchor.constraint(equalToConstant: 24),
            settings.heightAnchor.constraint(equalToConstant: 24),
            clear.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ]
        if let statusBadge {
            headerConstraints.append(contentsOf: [
                statusBadge.leadingAnchor.constraint(
                    greaterThanOrEqualTo: count.trailingAnchor,
                    constant: 12
                ),
                statusBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                clear.leadingAnchor.constraint(
                    greaterThanOrEqualTo: statusBadge.trailingAnchor,
                    constant: 8
                ),
            ])
        } else {
            headerConstraints.append(
                clear.leadingAnchor.constraint(
                    greaterThanOrEqualTo: count.trailingAnchor,
                    constant: 12
                )
            )
        }
        if let exclusion = Self.menuBarNotchExclusion(
            notchWidth: geometry.notchWidth,
            centerOffset: geometry.notchCenterOffset,
            hasHardwareNotch: geometry.hasHardwareNotch
        ) {
            let notchGuide = NSLayoutGuide()
            header.addLayoutGuide(notchGuide)
            let notchCenter = (exclusion.lowerBound + exclusion.upperBound) / 2
            let leftHeaderGroup: NSView = statusBadge.map { $0 as NSView } ?? count
            headerConstraints.append(contentsOf: [
                notchGuide.centerXAnchor.constraint(
                    equalTo: header.centerXAnchor,
                    constant: notchCenter
                ),
                notchGuide.widthAnchor.constraint(
                    equalToConstant: exclusion.upperBound - exclusion.lowerBound
                ),
                leftHeaderGroup.trailingAnchor.constraint(
                    lessThanOrEqualTo: notchGuide.leadingAnchor
                ),
                clear.leadingAnchor.constraint(
                    greaterThanOrEqualTo: notchGuide.trailingAnchor
                ),
            ])
        }
        NSLayoutConstraint.activate(headerConstraints)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(header)

        if let usageOverview {
            let limitView = WeeklyLimitView(overview: usageOverview, theme: theme)
            stack.addArrangedSubview(limitView)
            limitView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            weeklyLimitView = limitView
        }

        activeTaskRows.removeAll()
        if !displayedActiveTasks.isEmpty {
            let section = NSTextField(labelWithString: "ACTIVE")
            section.font = theme.font(ofSize: 9.5, weight: .bold)
            section.textColor = theme.tertiaryText
            section.translatesAutoresizingMaskIntoConstraints = false
            let sectionHost = NSView()
            sectionHost.translatesAutoresizingMaskIntoConstraints = false
            sectionHost.addSubview(section)
            NSLayoutConstraint.activate([
                sectionHost.heightAnchor.constraint(equalToConstant: 22),
                section.leadingAnchor.constraint(equalTo: sectionHost.leadingAnchor, constant: 14),
                section.bottomAnchor.constraint(equalTo: sectionHost.bottomAnchor, constant: -3),
            ])
            stack.addArrangedSubview(sectionHost)
            sectionHost.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            for (index, task) in displayedActiveTasks.enumerated() {
                let row = ActiveTaskRowView(task: task, index: index, theme: theme) { [weak self] in
                    self?.openActiveTask(task)
                }
                row.setShortcutLetterVisible(shortcutLettersVisible)
                activeTaskRows.append(row)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            if activeTasks.count > displayedActiveTasks.count {
                let remaining = NSTextField(labelWithString: "+ \(activeTasks.count - displayedActiveTasks.count) more active tasks")
                remaining.font = theme.font(ofSize: 10.5, weight: .medium)
                remaining.textColor = theme.secondaryText
                remaining.alignment = .center
                remaining.translatesAutoresizingMaskIntoConstraints = false
                remaining.heightAnchor.constraint(equalToConstant: 24).isActive = true
                stack.addArrangedSubview(remaining)
                remaining.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        if !completedTasks.isEmpty && !displayedActiveTasks.isEmpty {
            let section = NSTextField(labelWithString: "COMPLETED")
            section.font = theme.font(ofSize: 9.5, weight: .bold)
            section.textColor = theme.tertiaryText
            section.translatesAutoresizingMaskIntoConstraints = false
            section.heightAnchor.constraint(equalToConstant: 20).isActive = true
            stack.addArrangedSubview(section)
        }

        var rows: [TaskRowView] = []
        var rowLookup: [String: TaskRowView] = [:]
        for (index, task) in completedTasks.enumerated() {
            let shortcutIndex = displayedActiveTasks.count + index
            let row = TaskRowView(
                task: task,
                index: shortcutIndex,
                theme: theme,
                shouldReduceMotion: shouldReduceMotion,
                open: { [weak self] in self?.openTask(task) },
                dismiss: { [weak self] in self?.dismissTask(at: shortcutIndex) }
            )
            if dismissingEventIDs.contains(task.eventID) {
                row.holdInvisibleForPendingDismissal()
            }
            row.setShortcutLetterVisible(shortcutLettersVisible)
            rows.append(row)
            rowLookup[task.eventID] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if completedTasks.isEmpty && displayedActiveTasks.isEmpty {
            let emptyState = EmptyStateView(updateVersion: updateVersion, theme: theme)
            stack.addArrangedSubview(emptyState)
            emptyState.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            emptyStateView = emptyState
        }

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: geometry.bodyInset + 7
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -(geometry.bodyInset + 7)
            ),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
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
        let activeHeight = displayedActiveTasks.isEmpty ? 0 : 22 + displayedActiveTasks.count * 48 + (activeTasks.count > displayedActiveTasks.count ? 24 : 0)
        let completedSectionHeight = !completedTasks.isEmpty && !displayedActiveTasks.isEmpty ? 20 : 0
        let contentHeight: CGFloat = completedTasks.isEmpty && displayedActiveTasks.isEmpty
            ? 168
            : 62 + CGFloat(completedTasks.count * 48 + activeHeight + completedSectionHeight)
        let weeklyLimitHeight: CGFloat = usageOverview == nil ? 0 : 66
        // contentHeight historically included the 18-point gap below the hardware
        // notch. The header now occupies the menu-bar band, so reclaim that gap
        // while preserving every row's existing vertical rhythm.
        let height = contentHeight + weeklyLimitHeight - Self.reclaimedTopPadding
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
        guard pendingRebuild, !shortcutLettersVisible else { return }
        rebuildContent(initiallyExpanded: expanded)
        if expanded { positionPanel() }
    }

    private func positionPanel() {
        panel.setFrameOrigin(visibleOrigin())
    }

    private func orderPanelFront() {
        let wasVisible = panel.isVisible
        panel.orderFrontRegardless()
        if !wasVisible {
            startShortcutModifierMonitoring()
            onVisibilityChanged?(true)
        }
    }

    private func orderPanelOut() {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        if wasVisible {
            stopShortcutModifierMonitoring()
            onVisibilityChanged?(false)
        }
    }

    private func startShortcutModifierMonitoring() {
        refreshShortcutModifierState()
        guard shortcutModifierTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.refreshShortcutModifierState()
        }
        RunLoop.main.add(timer, forMode: .common)
        shortcutModifierTimer = timer
    }

    private func stopShortcutModifierMonitoring() {
        shortcutModifierTimer?.invalidate()
        shortcutModifierTimer = nil
        setShortcutLettersVisible(false)
    }

    private func refreshShortcutModifierState() {
        setShortcutLettersVisible(shortcutModifierState())
    }

    private func setShortcutLettersVisible(_ visible: Bool) {
        guard shortcutLettersVisible != visible else { return }
        if visible {
            lockedActiveTasks = displayedActiveTasks
            lockedCompletedTasks = presentedTasks
            hideTimer?.invalidate()
            makeEventPresentationPersistent()
        }
        shortcutLettersVisible = visible
        activeTaskRows.forEach { $0.setShortcutLetterVisible(visible) }
        rowsByEventID.values.forEach { $0.setShortcutLetterVisible(visible) }
        if let shortcutLockLabel {
            updateShortcutLockLabel(
                shortcutLockLabel,
                locked: visible,
                theme: ThemeStore.shared.activeTheme
            )
        }
        guard !visible else { return }
        lockedActiveTasks = nil
        lockedCompletedTasks = nil
        if phase == .open, panel.isVisible {
            finishPendingRebuild(expanded: true)
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
        }
    }

    private func makeEventPresentationPersistent() {
        guard eventAutoCloseCanBeCancelled, panel.isVisible else { return }
        eventAutoCloseCanBeCancelled = false
        isPinned = true
        hideTimer?.invalidate()
    }

    private func updateShortcutLockLabel(
        _ label: NSTextField,
        locked: Bool,
        theme: NotchTheme
    ) {
        label.stringValue = locked ? "LOCKED" : GlobalHotKeys.toggleShortcutLabel()
        label.font = .monospacedSystemFont(ofSize: locked ? 9.5 : 10.5, weight: .semibold)
        label.textColor = locked ? theme.accent : theme.secondaryText
        label.layer?.backgroundColor = locked
            ? theme.accent.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        label.toolTip = locked
            ? "Task order is frozen until Control and Shift are released"
            : "Show or hide Codex Notch"
        label.setAccessibilityLabel(locked ? "Shortcut order locked" : "Toggle Codex Notch")
        label.setAccessibilityValue(
            locked ? "Task order is frozen" : GlobalHotKeys.toggleShortcutLabel()
        )
    }

    private func screenFrame(_ row: TaskRowView) -> NSRect {
        panel.convertToScreen(row.convert(row.bounds, to: nil))
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
        let notch = ScreenNotchGeometry(screen: screen)
        let bodyInset: CGFloat = 34
        let bodyWidth = min(820, max(460, screen.frame.width - 160))
        return IslandGeometry(
            windowWidth: bodyWidth + bodyInset * 2,
            bodyInset: bodyInset,
            notchWidth: notch.width,
            notchHeight: notch.height,
            notchCenterOffset: notch.centerOffset,
            hasHardwareNotch: notch.hasHardwareNotch
        )
    }

    private static func menuBarNotchExclusion(
        notchWidth: CGFloat,
        centerOffset: CGFloat,
        hasHardwareNotch: Bool
    ) -> ClosedRange<CGFloat>? {
        guard hasHardwareNotch else { return nil }
        let halfWidth = notchWidth / 2 + hardwareNotchPadding
        return (centerOffset - halfWidth)...(centerOffset + halfWidth)
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screenParametersDidChange() {
        if deferVisibleRebuildWhileShortcutsLocked() { return }
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

    @discardableResult
    private func deferVisibleRebuildWhileShortcutsLocked() -> Bool {
        guard shortcutLettersVisible, panel.isVisible else { return false }
        pendingRebuild = true
        return true
    }
}
