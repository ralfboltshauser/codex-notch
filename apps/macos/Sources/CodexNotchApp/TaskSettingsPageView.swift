import AppKit

final class TaskSettingsPageView: NSView {
    private(set) var layoutViews: [String: NSView] = [:]
    private(set) var doNotDisturbButton: ClosureButton?
    private(set) var checkForUpdatesButton: ClosureButton?

    init(
        header: NSView,
        theme: NotchTheme,
        showsActiveTasks: Bool,
        doNotDisturbEnabled: Bool,
        versionDescription: String,
        toggleActiveTasks: @escaping () -> Void,
        toggleDoNotDisturb: @escaping () -> Void,
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
            "Choose what the notch shows and when it appears.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let activeTaskRow = preferenceRow(
            symbol: "bolt.horizontal.circle.fill",
            accessibilityDescription: "Active tasks",
            title: "Show active tasks",
            detail: "Live state is kept in memory only. Prompts, output, paths, and transcripts are never sent to the notch.",
            enabled: showsActiveTasks,
            toolTip: "Toggle active tasks",
            theme: theme,
            action: toggleActiveTasks
        )
        let doNotDisturbRow = preferenceRow(
            symbol: "moon.fill",
            accessibilityDescription: "Do Not Disturb",
            title: "Do Not Disturb",
            detail: "Stops automatic openings for finished tasks and updates. Manual shortcuts and sounds still work; macOS Focus is not used.",
            enabled: doNotDisturbEnabled,
            toolTip: "Toggle Do Not Disturb",
            theme: theme,
            action: toggleDoNotDisturb
        )
        doNotDisturbButton = doNotDisturbRow.button

        let preferenceCard = NSView()
        preferenceCard.translatesAutoresizingMaskIntoConstraints = false
        preferenceCard.wantsLayer = true
        preferenceCard.layer?.backgroundColor = theme.quietSurface.cgColor
        preferenceCard.layer?.borderColor = theme.border.cgColor
        preferenceCard.layer?.borderWidth = 1
        preferenceCard.layer?.cornerRadius = 14
        preferenceCard.layer?.cornerCurve = .continuous
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.border.cgColor
        [activeTaskRow.view, divider, doNotDisturbRow.view]
            .forEach(preferenceCard.addSubview)
        NSLayoutConstraint.activate([
            preferenceCard.heightAnchor.constraint(equalToConstant: 177),
            activeTaskRow.view.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor),
            activeTaskRow.view.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor),
            activeTaskRow.view.topAnchor.constraint(equalTo: preferenceCard.topAnchor),
            divider.leadingAnchor.constraint(equalTo: preferenceCard.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: preferenceCard.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: activeTaskRow.view.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            doNotDisturbRow.view.leadingAnchor.constraint(
                equalTo: preferenceCard.leadingAnchor
            ),
            doNotDisturbRow.view.trailingAnchor.constraint(
                equalTo: preferenceCard.trailingAnchor
            ),
            doNotDisturbRow.view.topAnchor.constraint(equalTo: divider.bottomAnchor),
            doNotDisturbRow.view.bottomAnchor.constraint(equalTo: preferenceCard.bottomAnchor),
        ])

        let shortcutTitle = SettingsViewFactory.label(
            "QUICK TOGGLE",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText,
            theme: theme
        )
        let shortcutCard = NSView()
        shortcutCard.translatesAutoresizingMaskIntoConstraints = false
        shortcutCard.wantsLayer = true
        shortcutCard.layer?.backgroundColor = theme.surface.cgColor
        shortcutCard.layer?.cornerRadius = 12
        shortcutCard.layer?.cornerCurve = .continuous
        let shortcutDetail = SettingsViewFactory.label(
            "Show or hide active tasks from anywhere",
            size: 13,
            weight: .medium,
            color: theme.primaryText,
            theme: theme
        )
        shortcutDetail.lineBreakMode = .byTruncatingTail
        shortcutDetail.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        let keys = SettingsViewFactory.label(
            GlobalHotKeys.activeTasksShortcutLabel(),
            size: 12,
            weight: .semibold,
            color: theme.accent,
            theme: theme
        )
        keys.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keys.alignment = .center
        keys.setContentHuggingPriority(.required, for: .horizontal)
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)
        [shortcutDetail, keys].forEach(shortcutCard.addSubview)
        NSLayoutConstraint.activate([
            shortcutCard.heightAnchor.constraint(equalToConstant: 58),
            shortcutDetail.leadingAnchor.constraint(
                equalTo: shortcutCard.leadingAnchor,
                constant: 16
            ),
            shortcutDetail.centerYAnchor.constraint(equalTo: shortcutCard.centerYAnchor),
            shortcutDetail.trailingAnchor.constraint(
                lessThanOrEqualTo: keys.leadingAnchor,
                constant: -16
            ),
            keys.trailingAnchor.constraint(equalTo: shortcutCard.trailingAnchor, constant: -16),
            keys.centerYAnchor.constraint(equalTo: shortcutCard.centerYAnchor),
        ])
        layoutViews["Quick Toggle.title"] = shortcutDetail
        layoutViews["Quick Toggle.keys"] = keys

        let note = SettingsViewFactory.label(
            "Finished tasks are still collected in Do Not Disturb and remain available with \(GlobalHotKeys.toggleShortcutLabel()).",
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        note.maximumNumberOfLines = 2
        let footer = SettingsViewFactory.standardFooter(
            versionDescription: versionDescription,
            theme: theme,
            checkForUpdates: checkForUpdates,
            close: close
        )
        checkForUpdatesButton = footer.checkForUpdates

        let stack = NSStackView(views: [
            header,
            title,
            subtitle,
            preferenceCard,
            shortcutTitle,
            shortcutCard,
            note,
            footer.view,
        ])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(26, after: preferenceCard)
        stack.setCustomSpacing(9, after: shortcutTitle)
        stack.setCustomSpacing(20, after: shortcutCard)
        stack.setCustomSpacing(30, after: note)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preferenceCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            footer.checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            footer.done.widthAnchor.constraint(equalToConstant: 96),
            footer.done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: toggle.leadingAnchor,
                constant: -12
            ),
            detailLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            detailLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
        ])
        layoutViews["\(title).title"] = label
        layoutViews["\(title).detail"] = detailLabel
        layoutViews["\(title).toggle"] = toggle
        return (row, toggle)
    }
}
