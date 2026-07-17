import AppKit
import QuartzCore

final class TaskRowView: NSView {
    let task: CompletedTask

    private let openHandler: () -> Void
    private let shouldReduceMotion: () -> Bool
    private let dismissButton: ClosureButton
    private let numberBadge: NumberBadgeView
    private let outcomeLabel: NSTextField?
    private let relativeTimeLabel: NSTextField
    private let theme: NotchTheme
    private var tracking: NSTrackingArea?
    private var isHovered = false
    private var isTrackingPress = false
    private var isPressed = false
    private var isDismissing = false
    private var isTriggered: Bool

    init(
        task: CompletedTask,
        index: Int,
        theme: NotchTheme,
        now: Date,
        isTriggered: Bool,
        showsOutcome: Bool = true,
        shouldReduceMotion: @escaping () -> Bool,
        open: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.task = task
        self.theme = theme
        self.shouldReduceMotion = shouldReduceMotion
        self.isTriggered = isTriggered
        openHandler = open
        dismissButton = ClosureButton(handler: dismiss)
        outcomeLabel = showsOutcome
            ? task.outcome.map { NSTextField(labelWithString: $0) }
            : nil
        relativeTimeLabel = NSTextField(
            labelWithString: CompletionRelativeTime.text(since: task.receivedAt, now: now)
        )
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
        layer?.backgroundColor = (isTriggered ? theme.surface : NSColor.clear).cgColor
        layer?.borderWidth = isTriggered ? 1 : 0
        layer?.borderColor = theme.accent.withAlphaComponent(0.28).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        let title = NSTextField(labelWithString: task.title)
        title.font = theme.font(ofSize: 14, weight: .medium)
        title.textColor = theme.primaryText
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        outcomeLabel?.font = theme.font(ofSize: 10.5, weight: .regular)
        outcomeLabel?.textColor = theme.secondaryText
        outcomeLabel?.lineBreakMode = .byTruncatingTail
        outcomeLabel?.maximumNumberOfLines = 1
        outcomeLabel?.translatesAutoresizingMaskIntoConstraints = false
        outcomeLabel?.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let source = NSTextField(labelWithString: task.sourceLabel)
        source.font = theme.font(ofSize: 10.5, weight: .medium)
        source.textColor = theme.secondaryText
        source.lineBreakMode = .byTruncatingTail
        source.translatesAutoresizingMaskIntoConstraints = false
        source.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        relativeTimeLabel.font = theme.font(ofSize: 10.5, weight: .medium)
        relativeTimeLabel.textColor = isTriggered
            ? theme.accent.withAlphaComponent(0.82)
            : theme.tertiaryText
        relativeTimeLabel.lineBreakMode = .byTruncatingTail
        relativeTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        relativeTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        relativeTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let shortcut = NSTextField(
            labelWithString: GlobalHotKeys.openShortcutLabel(at: index) ?? ""
        )
        shortcut.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcut.textColor = theme.secondaryText
        shortcut.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Dismiss task"
        )
        dismissButton.contentTintColor = theme.secondaryText
        dismissButton.toolTip = GlobalHotKeys.dismissShortcutLabel(at: index)
            .map { "Dismiss — \($0)" } ?? "Dismiss"
        dismissButton.alphaValue = 0
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        var rowViews: [NSView] = [numberBadge, title]
        if let outcomeLabel { rowViews.append(outcomeLabel) }
        rowViews.append(contentsOf: [source, relativeTimeLabel, shortcut, dismissButton])
        rowViews.forEach(addSubview)
        var constraints = [
            heightAnchor.constraint(equalToConstant: 46),
            numberBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            numberBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: numberBadge.trailingAnchor, constant: 11),
            source.leadingAnchor.constraint(
                greaterThanOrEqualTo: title.trailingAnchor,
                constant: 14
            ),
            source.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            relativeTimeLabel.leadingAnchor.constraint(
                equalTo: source.trailingAnchor,
                constant: 10
            ),
            shortcut.leadingAnchor.constraint(
                equalTo: relativeTimeLabel.trailingAnchor,
                constant: 12
            ),
            dismissButton.leadingAnchor.constraint(equalTo: shortcut.trailingAnchor, constant: 8),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24),
        ]
        if let outcomeLabel {
            constraints.append(contentsOf: [
                title.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -7),
                source.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                relativeTimeLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                shortcut.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                outcomeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                outcomeLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: -1),
                outcomeLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: dismissButton.leadingAnchor,
                    constant: -8
                ),
            ])
        } else {
            constraints.append(contentsOf: [
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
                source.centerYAnchor.constraint(equalTo: centerYAnchor),
                relativeTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        updateAccessibilityValue()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setShortcutLetterVisible(_ visible: Bool) {
        numberBadge.showShortcut(visible)
    }

    func setTriggered(_ triggered: Bool, animated: Bool = true) {
        guard isTriggered != triggered else { return }
        isTriggered = triggered
        relativeTimeLabel.textColor = triggered
            ? theme.accent.withAlphaComponent(0.82)
            : theme.tertiaryText
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.borderWidth = triggered ? 1 : 0
        layer?.borderColor = theme.accent.withAlphaComponent(0.28).cgColor
        CATransaction.commit()
        updateAccessibilityValue()
        updateAppearance(
            duration: animated ? NotchMotion.reducedMotionFadeDuration : 0,
            timingFunction: NotchMotion.easeOut
        )
    }

    func updateRelativeTime(now: Date) {
        relativeTimeLabel.stringValue = CompletionRelativeTime.text(
            since: task.receivedAt,
            now: now
        )
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        setAccessibilityLabel(task.title)
        let age = relativeTimeLabel.stringValue
        let outcome = task.outcome.map { value in
            let needsPunctuation = value.last.map { !".!?".contains($0) } ?? false
            return "Outcome: \(value)\(needsPunctuation ? "." : "") "
        } ?? ""
        setAccessibilityValue(
            outcome + (isTriggered ? "Triggered this opening. \(age)." : age)
        )
    }

    var badgeTextForTesting: String { numberBadge.textForTesting }
    var outcomeTextForTesting: String? { outcomeLabel?.stringValue }
    var relativeTimeTextForTesting: String { relativeTimeLabel.stringValue }
    var isTriggeredForTesting: Bool { isTriggered }
    var hasPromotionAnimationForTesting: Bool {
        layer?.animation(forKey: "rowPromotion") is CASpringAnimation
    }

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
        let restingBackground = isTriggered ? theme.surface : NSColor.clear
        let targetBackground = (
            isPressed ? theme.pressedSurface : (isHovered ? theme.hoverSurface : restingBackground)
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

    func animatePromotion(from oldFrame: NSRect, to newFrame: NSRect) {
        guard let layer else { return }
        let deltaX = oldFrame.midX - newFrame.midX
        let deltaY = oldFrame.midY - newFrame.midY
        guard abs(deltaX) > 0.5 || abs(deltaY) > 0.5 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.removeAnimation(forKey: "rowReflow")
        layer.removeAnimation(forKey: "rowPromotion")
        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = NotchMotion.promotionMass
        spring.stiffness = NotchMotion.promotionStiffness
        spring.damping = NotchMotion.promotionDamping
        spring.initialVelocity = 0
        spring.fromValue = CATransform3DMakeTranslation(deltaX, deltaY, 0)
        spring.toValue = CATransform3DIdentity
        spring.duration = NotchMotion.promotionDuration
        layer.add(spring, forKey: "rowPromotion")
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
        if !isPressed {
            updateAppearance(duration: 0.12, timingFunction: NotchMotion.ease)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = NotchMotion.ease
            dismissButton.animator().alphaValue = 0
        }
    }
}
