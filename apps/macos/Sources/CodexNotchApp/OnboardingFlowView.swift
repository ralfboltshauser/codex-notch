import AppKit
import QuartzCore

final class OnboardingFlowView: NSView {
    private(set) var journey: OnboardingJourney
    private let reduceMotion: () -> Bool
    private let body = NSView()
    private let progress = OnboardingProgressView()
    private let stepLabel = NSTextField(labelWithString: "")
    private let primary = ClosureButton()
    private let secondary = ClosureButton()
    private var transitionID = 0
    private var errorMessage: String?

    var onInstallHook: (() -> Void)?
    var onReviewHook: (() -> Void)?
    var onTryNotch: (() -> Void)?
    var onFinish: (() -> Void)?
    var onSkip: (() -> Void)?

    var stepForTesting: OnboardingStep { journey.step }
    var primaryButtonForTesting: NSButton { primary }
    var secondaryButtonForTesting: NSButton { secondary }
    var bodyHasAmbiguousLayoutForTesting: Bool {
        layoutSubtreeIfNeeded()
        return body.subviews.contains(where: \.hasAmbiguousLayout)
    }

    init(
        journey: OnboardingJourney,
        reduceMotion: @escaping () -> Bool
    ) {
        self.journey = journey
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let theme = ThemeStore.shared.activeTheme

        let mark = NSImageView(image: NSImage(
            systemSymbolName: "sparkles.rectangle.stack.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        mark.contentTintColor = theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        let product = SettingsViewFactory.label(
            "Codex Notch",
            size: 13.5,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        stepLabel.font = theme.font(ofSize: 10, weight: .semibold)
        stepLabel.textColor = theme.tertiaryText
        stepLabel.alignment = .right
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        let header = NSStackView(views: [mark, product, NSView(), stepLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9
        header.translatesAutoresizingMaskIntoConstraints = false

        body.translatesAutoresizingMaskIntoConstraints = false
        body.wantsLayer = true

        primary.handler = { [weak self] in self?.handlePrimary() }
        secondary.handler = { [weak self] in self?.handleSecondary() }
        SettingsViewFactory.style(primary, as: .primary, theme: theme)
        SettingsViewFactory.style(secondary, as: .secondary, theme: theme)
        primary.keyEquivalent = "\r"
        let footer = NSStackView(views: [secondary, NSView(), primary])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false

        [header, progress, body, footer].forEach(addSubview)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
            mark.widthAnchor.constraint(equalToConstant: 18),
            mark.heightAnchor.constraint(equalToConstant: 18),
            progress.leadingAnchor.constraint(equalTo: leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: trailingAnchor),
            progress.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 13),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 22),
            body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 42),
            secondary.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            secondary.heightAnchor.constraint(equalToConstant: 40),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 152),
            primary.heightAnchor.constraint(equalToConstant: 40),
        ])
        render(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateHook(
        installed: Bool,
        trusted: Bool,
        error: String? = nil,
        preserveError: Bool = false
    ) {
        let nextError = preserveError ? errorMessage : error
        let changed = installed != journey.hookInstalled
            || trusted != journey.hookTrusted
            || nextError != errorMessage
        journey.updateHook(installed: installed, trusted: trusted)
        errorMessage = nextError
        guard changed, journey.step == .connect else { return }
        render(animated: true)
    }

    func notchVisibilityChanged(_ visible: Bool) {
        guard visible, journey.step == .practice, !journey.openedNotch else { return }
        journey.markNotchOpened()
        render(animated: true)
    }

    private func handlePrimary() {
        switch journey.step {
        case .welcome:
            _ = journey.advance()
            render(animated: true)
        case .connect:
            if !journey.hookInstalled {
                errorMessage = nil
                onInstallHook?()
            } else if !journey.hookTrusted {
                errorMessage = nil
                onReviewHook?()
            } else {
                _ = journey.advance()
                render(animated: true)
            }
        case .practice:
            if journey.openedNotch {
                _ = journey.advance()
                render(animated: true)
            } else {
                onTryNotch?()
            }
        case .ready:
            onFinish?()
        }
    }

    private func handleSecondary() {
        if journey.step == .welcome {
            onSkip?()
            return
        }
        _ = journey.goBack()
        errorMessage = nil
        render(animated: true)
    }

    private func render(animated: Bool) {
        transitionID &+= 1
        let currentTransition = transitionID
        progress.update(step: journey.step, theme: ThemeStore.shared.activeTheme)
        stepLabel.stringValue = "\(journey.step.rawValue + 1) OF \(OnboardingStep.allCases.count)"
        secondary.title = journey.step == .welcome ? "Skip for Now" : "Back"
        primary.title = primaryTitle
        primary.isEnabled = true
        primary.toolTip = primaryTooltip

        let build = { [weak self] in
            guard let self, self.transitionID == currentTransition else { return }
            self.body.subviews.forEach { $0.removeFromSuperview() }
            let content = self.makeBody(for: self.journey.step)
            content.translatesAutoresizingMaskIntoConstraints = false
            self.body.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: self.body.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: self.body.trailingAnchor),
                content.topAnchor.constraint(equalTo: self.body.topAnchor),
                content.bottomAnchor.constraint(lessThanOrEqualTo: self.body.bottomAnchor),
            ])
            self.body.layoutSubtreeIfNeeded()
            self.animateBodyIn(ifNeeded: animated)
        }

        guard animated, window?.isVisible == true, let layer = body.layer else {
            build()
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = 0
        fade.duration = 0.08
        fade.timingFunction = NotchMotion.easeOut
        layer.opacity = 0
        layer.add(fade, forKey: "onboardingBodyOut")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: build)
    }

    private func animateBodyIn(ifNeeded animated: Bool) {
        guard animated, let layer = body.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = reduceMotion() ? NotchMotion.reducedMotionFadeDuration : 0.20
        fade.timingFunction = NotchMotion.easeOut
        if reduceMotion() {
            layer.add(fade, forKey: "onboardingBodyIn")
        } else {
            let move = CABasicAnimation(keyPath: "transform.translation.x")
            move.fromValue = 10
            move.toValue = 0
            move.duration = 0.22
            move.timingFunction = NotchMotion.easeOut
            let group = CAAnimationGroup()
            group.animations = [fade, move]
            group.duration = 0.22
            group.timingFunction = NotchMotion.easeOut
            layer.add(group, forKey: "onboardingBodyIn")
        }
    }

    private var primaryTitle: String {
        switch journey.step {
        case .welcome: return "Set Up Codex Notch"
        case .connect:
            if !journey.hookInstalled { return "Install Completion Hook" }
            if !journey.hookTrusted { return "Review in Codex…" }
            return "Continue"
        case .practice:
            return journey.openedNotch ? "Continue" : "Open Codex Notch"
        case .ready: return "Start Using Codex Notch"
        }
    }

    private var primaryTooltip: String? {
        switch journey.step {
        case .connect where !journey.hookInstalled:
            return "Add the local Codex Stop hook"
        case .connect where !journey.hookTrusted:
            return "Open Codex and approve the new local hook"
        case .practice where !journey.openedNotch:
            return "Show the real Codex Notch"
        default: return nil
        }
    }

    private func makeBody(for step: OnboardingStep) -> NSView {
        switch step {
        case .welcome: return makeWelcomeBody()
        case .connect: return makeConnectBody()
        case .practice: return makePracticeBody()
        case .ready: return makeReadyBody()
        }
    }

    private func makeWelcomeBody() -> NSView {
        let preview = OnboardingNotchPreviewView(mode: .waiting, reduceMotion: reduceMotion)
        preview.heightAnchor.constraint(equalToConstant: 188).isActive = true
        let stack = pageStack(
            title: "Know the moment Codex is done.",
            subtitle: "Codex Notch keeps every completion at the top of your screen, so you can stay in flow and return at exactly the right moment.",
            content: [preview]
        )
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[1])
        return stack
    }

    private func makeConnectBody() -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let installed = OnboardingStatusRow(
            title: "Completion hook",
            detail: journey.hookInstalled ? "Installed locally" : "Tells the notch when a turn finishes",
            complete: journey.hookInstalled,
            theme: theme
        )
        let trusted = OnboardingStatusRow(
            title: "Codex approval",
            detail: journey.hookTrusted ? "Approved and ready" : "You review the hook before Codex runs it",
            complete: journey.hookTrusted,
            theme: theme
        )
        let statuses = NSStackView(views: [installed, trusted])
        statuses.orientation = .horizontal
        statuses.spacing = 10
        statuses.distribution = .fillEqually
        let privacy = callout(
            symbol: "lock.shield.fill",
            text: "Only task title, thread ID, source, and completion time are stored. Prompts and output stay in Codex.",
            color: theme.accent
        )
        var content: [NSView] = [statuses, privacy]
        if let errorMessage {
            content.append(callout(symbol: "exclamationmark.triangle.fill", text: errorMessage, color: .systemRed))
        }
        return pageStack(
            title: "One local connection. Nothing to upload.",
            subtitle: "Install the bundled Stop hook, then approve it in Codex. Both steps are visible and reversible.",
            content: content
        )
    }

    private func makePracticeBody() -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let keys = NSStackView(views: [
            OnboardingKeycapView("⌃", theme: theme),
            OnboardingKeycapView("⇧", theme: theme),
            OnboardingKeycapView("H", theme: theme),
        ])
        keys.orientation = .horizontal
        keys.alignment = .centerY
        keys.spacing = 8
        let keyCard = lessonCard(
            symbol: journey.openedNotch ? "checkmark.circle.fill" : "keyboard.fill",
            title: journey.openedNotch ? "That’s it." : "Open it from anywhere",
            detail: journey.openedNotch
                ? "The shortcut is ready whenever you need the full task list."
                : "Press Control–Shift–H now, or use the button below.",
            accessory: keys,
            emphasized: journey.openedNotch
        )
        let hoverCard = lessonCard(
            symbol: "arrow.up.to.line.compact",
            title: "Or just move to the notch",
            detail: "Hover at the top center of the screen for a smooth, hands-free open.",
            accessory: nil,
            emphasized: false
        )
        return pageStack(
            title: "Make it muscle memory.",
            subtitle: "The notch opens automatically for completions. These two gestures bring it back whenever you want it.",
            content: [keyCard, hoverCard]
        )
    }

    private func makeReadyBody() -> NSView {
        let preview = OnboardingNotchPreviewView(mode: .success, reduceMotion: reduceMotion)
        preview.heightAnchor.constraint(equalToConstant: 188).isActive = true
        DispatchQueue.main.async { preview.playSuccessAnimation() }
        let stack = pageStack(
            title: "You’re ready. Stay in the flow.",
            subtitle: "Keep working in Codex. The next completed task will arrive in the notch, remain one shortcut away, and never steal focus.",
            content: [preview]
        )
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[1])
        return stack
    }

    private func pageStack(title: String, subtitle: String, content: [NSView]) -> NSStackView {
        let theme = ThemeStore.shared.activeTheme
        let eyebrow = SettingsViewFactory.label(
            journey.step.eyebrow,
            size: 9.5,
            weight: .bold,
            color: theme.accent.withAlphaComponent(0.82),
            theme: theme
        )
        let heading = SettingsViewFactory.label(
            title,
            size: 28,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let detail = SettingsViewFactory.label(
            subtitle,
            size: 13.5,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        let stack = NSStackView(views: [eyebrow, heading, detail] + content)
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 8
        stack.setCustomSpacing(4, after: eyebrow)
        stack.setCustomSpacing(20, after: detail)
        NSLayoutConstraint.activate(content.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        return stack
    }

    private func callout(symbol: String, text: String, color: NSColor) -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 11
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = theme.quietSurface.cgColor
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = SettingsViewFactory.label(
            text,
            size: 11,
            weight: .medium,
            color: theme.secondaryText,
            theme: theme
        )
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        [icon, label].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func lessonCard(
        symbol: String,
        title: String,
        detail: String,
        accessory: NSView?,
        emphasized: Bool
    ) -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = (
            emphasized ? theme.surface : theme.quietSurface
        ).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = (
            emphasized ? theme.accent.withAlphaComponent(0.38) : theme.border
        ).cgColor
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = emphasized ? theme.accent : theme.secondaryText
        icon.translatesAutoresizingMaskIntoConstraints = false
        let heading = SettingsViewFactory.label(
            title,
            size: 13.5,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let label = SettingsViewFactory.label(
            detail,
            size: 11,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let text = NSStackView(views: [heading, label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false
        [icon, text].forEach(card.addSubview)
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(accessory)
        }
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 82),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 13),
            text.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: accessory?.leadingAnchor ?? card.trailingAnchor, constant: accessory == nil ? -16 : -18),
        ])
        if let accessory {
            NSLayoutConstraint.activate([
                accessory.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                accessory.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            ])
        }
        return card
    }
}
