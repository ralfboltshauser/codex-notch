import AppKit

final class TaskSettingsPageView: NSView {
    private(set) var layoutViews: [String: NSView] = [:]
    private(set) var completionOutcomeButton: ClosureButton?
    private(set) var attentionModeButtons: [AttentionMode: ClosureButton] = [:]
    private(set) var checkForUpdatesButton: ClosureButton?

    init(
        header: NSView,
        theme: NotchTheme,
        showsActiveTasks: Bool,
        showsCompletionOutcomes: Bool,
        attentionMode: AttentionMode,
        versionDescription: String,
        toggleActiveTasks: @escaping () -> Void,
        toggleCompletionOutcomes: @escaping () -> Void,
        setAttentionMode: @escaping (AttentionMode) -> Void,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        super.init(frame: .zero)

        let title = SettingsViewFactory.label(
            "Task behavior",
            size: 25,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let subtitle = SettingsViewFactory.label(
            "Choose what the notch reveals and how it asks for your attention.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let activeTaskRow = preferenceRow(
            symbol: "bolt.horizontal.circle.fill",
            accessibilityDescription: "Active tasks",
            title: "Show active tasks",
            detail: "Keep live root tasks in memory and roll collaborating agents into their parent task.",
            enabled: showsActiveTasks,
            toolTip: "Toggle active tasks",
            theme: theme,
            action: toggleActiveTasks
        )
        let outcomeRow = preferenceRow(
            symbol: "text.bubble.fill",
            accessibilityDescription: "Completion outcomes",
            title: "Show completion outcomes",
            detail: "Show one bounded line from Codex’s final response beneath local completed tasks. It is stored only on this Mac.",
            enabled: showsCompletionOutcomes,
            toolTip: "Toggle completion outcomes",
            theme: theme,
            action: toggleCompletionOutcomes
        )
        completionOutcomeButton = outcomeRow.button
        let attentionRow = attentionPreferenceRow(
            selectedMode: attentionMode,
            theme: theme,
            select: setAttentionMode
        )
        attentionModeButtons = attentionRow.buttons

        let preferenceCard = NSView()
        preferenceCard.translatesAutoresizingMaskIntoConstraints = false
        preferenceCard.wantsLayer = true
        preferenceCard.layer?.backgroundColor = theme.quietSurface.cgColor
        preferenceCard.layer?.borderColor = theme.border.cgColor
        preferenceCard.layer?.borderWidth = 1
        preferenceCard.layer?.cornerRadius = 14
        preferenceCard.layer?.cornerCurve = .continuous
        let firstDivider = divider(theme: theme)
        let secondDivider = divider(theme: theme)
        [
            activeTaskRow.view,
            firstDivider,
            outcomeRow.view,
            secondDivider,
            attentionRow.view,
        ].forEach(preferenceCard.addSubview)
        NSLayoutConstraint.activate([
            preferenceCard.heightAnchor.constraint(equalToConstant: 296),
            activeTaskRow.view.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor),
            activeTaskRow.view.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor),
            activeTaskRow.view.topAnchor.constraint(equalTo: preferenceCard.topAnchor),
            firstDivider.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor, constant: 18),
            firstDivider.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor, constant: -18),
            firstDivider.topAnchor.constraint(equalTo: activeTaskRow.view.bottomAnchor),
            firstDivider.heightAnchor.constraint(equalToConstant: 1),
            outcomeRow.view.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor),
            outcomeRow.view.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor),
            outcomeRow.view.topAnchor.constraint(equalTo: firstDivider.bottomAnchor),
            secondDivider.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor, constant: 18),
            secondDivider.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor, constant: -18),
            secondDivider.topAnchor.constraint(equalTo: outcomeRow.view.bottomAnchor),
            secondDivider.heightAnchor.constraint(equalToConstant: 1),
            attentionRow.view.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor),
            attentionRow.view.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor),
            attentionRow.view.topAnchor.constraint(equalTo: secondDivider.bottomAnchor),
            attentionRow.view.bottomAnchor.constraint(equalTo: preferenceCard.bottomAnchor),
        ])

        let footer = SettingsViewFactory.standardFooter(
            versionDescription: versionDescription,
            theme: theme,
            checkForUpdates: checkForUpdates,
            close: close
        )
        checkForUpdatesButton = footer.checkForUpdates

        let stack = NSStackView(views: [header, title, subtitle, preferenceCard, footer.view])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(34, after: preferenceCard)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preferenceCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            footer.checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            footer.done.widthAnchor.constraint(equalToConstant: 96),
            footer.done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func divider(theme: NotchTheme) -> NSView {
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.border.cgColor
        return divider
    }

    private func preferenceRow(
        symbol: String,
        accessibilityDescription: String,
        title: String,
        detail: String,
        enabled: Bool,
        toolTip: String,
        theme: NotchTheme,
        action: @escaping () -> Void
    ) -> (view: NSView, button: ClosureButton) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityDescription
        ) ?? NSImage())
        icon.contentTintColor = theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = SettingsViewFactory.label(
            title,
            size: 14,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detailLabel = SettingsViewFactory.label(
            detail,
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toggle = ClosureButton(handler: action)
        toggle.title = enabled ? "On" : "Off"
        toggle.image = NSImage(
            systemSymbolName: enabled ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: "\(title) \(enabled ? "on" : "off")"
        )
        toggle.imagePosition = .imageLeading
        toggle.font = .systemFont(ofSize: 12, weight: .semibold)
        toggle.contentTintColor = enabled ? theme.accent : theme.secondaryText
        toggle.toolTip = toolTip
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        [icon, label, detailLabel, toggle].forEach(row.addSubview)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 88),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            icon.topAnchor.constraint(equalTo: row.topAnchor, constant: 17),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 16),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            toggle.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 68),
            toggle.heightAnchor.constraint(equalToConstant: 30),
            label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
            detailLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            detailLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
        ])
        layoutViews["\(title).title"] = label
        layoutViews["\(title).detail"] = detailLabel
        layoutViews["\(title).toggle"] = toggle
        return (row, toggle)
    }

    private func attentionPreferenceRow(
        selectedMode: AttentionMode,
        theme: NotchTheme,
        select: @escaping (AttentionMode) -> Void
    ) -> (view: NSView, buttons: [AttentionMode: ClosureButton]) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(
            systemSymbolName: "bell.badge.fill",
            accessibilityDescription: "Attention mode"
        ) ?? NSImage())
        icon.contentTintColor = theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = SettingsViewFactory.label(
            "Attention",
            size: 14,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let detail = SettingsViewFactory.label(
            "Notify opens completions with sound. Glance badges them. Tasks needing you open in either; Quiet only collects.",
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping
        let buttons: [AttentionMode: ClosureButton] = Dictionary(
            uniqueKeysWithValues: AttentionMode.allCases.map { mode in
                let isSelected = mode == selectedMode
                let button = AttentionChoiceButton()
                button.title = mode.title
                button.image = NSImage(
                    systemSymbolName: mode.systemImageName,
                    accessibilityDescription: nil
                )
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true
                button.font = theme.font(ofSize: 11.5, weight: .semibold)
                button.contentTintColor = isSelected
                    ? theme.primaryText
                    : theme.secondaryText
                button.wantsLayer = true
                button.layer?.backgroundColor = (
                    isSelected ? theme.accent.withAlphaComponent(0.16) : theme.surface
                ).cgColor
                button.layer?.borderColor = (
                    isSelected ? theme.accent.withAlphaComponent(0.62) : theme.border
                ).cgColor
                button.layer?.borderWidth = 1
                button.layer?.cornerRadius = 9
                button.layer?.cornerCurve = .continuous
                button.toolTip = mode.helpText
                button.setButtonType(.radio)
                button.state = isSelected ? .on : .off
                button.refusesFirstResponder = false
                button.setAccessibilityRole(.radioButton)
                button.setAccessibilityLabel("\(mode.title) attention mode")
                button.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
                button.setAccessibilityHelp(mode.helpText)
                button.translatesAutoresizingMaskIntoConstraints = false
                return (mode, button as ClosureButton)
            }
        )
        for mode in AttentionMode.allCases {
            guard let button = buttons[mode] as? AttentionChoiceButton else { continue }
            button.handler = { [weak self] in
                self?.chooseAttentionMode(mode, theme: theme, select: select)
            }
            button.onMoveSelection = { [weak self] direction in
                self?.moveAttentionSelection(
                    from: mode,
                    direction: direction,
                    theme: theme,
                    select: select
                )
            }
        }
        let choices = NSStackView(views: AttentionMode.allCases.compactMap { buttons[$0] })
        choices.orientation = .horizontal
        choices.alignment = .centerY
        choices.distribution = .fillEqually
        choices.spacing = 8
        choices.translatesAutoresizingMaskIntoConstraints = false
        [icon, title, detail, choices].forEach(row.addSubview)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 118),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            icon.topAnchor.constraint(equalTo: row.topAnchor, constant: 17),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 16),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            choices.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            choices.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            choices.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -13),
            choices.heightAnchor.constraint(equalToConstant: 32),
        ])
        for mode in AttentionMode.allCases {
            guard let button = buttons[mode] else { continue }
            layoutViews["Attention.\(mode.title)"] = button
        }
        layoutViews["Attention.title"] = title
        layoutViews["Attention.detail"] = detail
        return (row, buttons)
    }

    private func moveAttentionSelection(
        from mode: AttentionMode,
        direction: Int,
        theme: NotchTheme,
        select: (AttentionMode) -> Void
    ) {
        let modes = AttentionMode.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        let nextIndex = min(
            max(index + direction, modes.startIndex),
            modes.index(before: modes.endIndex)
        )
        chooseAttentionMode(modes[nextIndex], theme: theme, select: select)
        attentionModeButtons[modes[nextIndex]]?.window?.makeFirstResponder(
            attentionModeButtons[modes[nextIndex]]
        )
    }

    private func chooseAttentionMode(
        _ selectedMode: AttentionMode,
        theme: NotchTheme,
        select: (AttentionMode) -> Void
    ) {
        for mode in AttentionMode.allCases {
            guard let button = attentionModeButtons[mode] else { continue }
            let selected = mode == selectedMode
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? theme.primaryText : theme.secondaryText
            button.layer?.backgroundColor = (
                selected ? theme.accent.withAlphaComponent(0.16) : theme.surface
            ).cgColor
            button.layer?.borderColor = (
                selected ? theme.accent.withAlphaComponent(0.62) : theme.border
            ).cgColor
            button.setAccessibilityValue(selected ? "Selected" : "Not selected")
        }
        select(selectedMode)
    }
}

private final class AttentionChoiceButton: ClosureButton {
    var onMoveSelection: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onMoveSelection?(-1)
        case 124: onMoveSelection?(1)
        default: super.keyDown(with: event)
        }
    }
}
