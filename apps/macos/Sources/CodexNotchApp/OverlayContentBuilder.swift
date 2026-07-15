import AppKit

struct OverlayContentConfiguration {
    let geometry: IslandGeometry
    let theme: NotchTheme
    let completedTasks: [CompletedTask]
    let displayedActiveTasks: [ActiveTask]
    let totalActiveTaskCount: Int
    let showsActiveTasks: Bool
    let shortcutLettersVisible: Bool
    let updateVersion: String?
    let usageState: CodexUsageState
    let hostHealth: HostHealthOverview
    let triggeringEventID: String?
    let dismissingEventIDs: Set<String>
    let now: Date
    let notchExclusion: ClosedRange<CGFloat>?
    let shouldReduceMotion: () -> Bool
}

struct OverlayContentActions {
    let refreshUsage: () -> Void
    let openConnections: () -> Void
    let toggleActiveTasks: () -> Void
    let clearTasks: () -> Void
    let openSettings: () -> Void
    let installUpdate: () -> Void
    let openActiveTask: (ActiveTask) -> Void
    let openCompletedTask: (CompletedTask) -> Void
    let dismissTask: (Int) -> Void
    let hoverChanged: (Bool) -> Void
}

struct BuiltOverlayContent {
    let root: HUDContentView
    let size: NSSize
    let rowsByEventID: [String: TaskRowView]
    let activeTaskRows: [ActiveTaskRowView]
    let activeSectionLabel: NSTextField?
    let activeFreezeLabel: NSTextField?
    let emptyStateView: EmptyStateView?
    let updateButton: ClosureButton
    let settingsButton: ClosureButton
    let hostStatusBadge: HostStatusBadgeView
    let weeklyUsageBadge: WeeklyUsageHeaderView?
    let shortcutHintLabel: NSTextField
}

enum OverlayContentBuilder {
    static let menuBarHeaderHeight: CGFloat = 36
    static let reclaimedTopPadding: CGFloat = 18

    static func build(
        configuration: OverlayContentConfiguration,
        actions: OverlayContentActions
    ) -> BuiltOverlayContent {
        let theme = configuration.theme
        let geometry = configuration.geometry
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

        let toggleHint = NSTextField(labelWithString: GlobalHotKeys.toggleShortcutLabel())
        toggleHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        toggleHint.alignment = .center
        toggleHint.wantsLayer = true
        toggleHint.layer?.cornerRadius = 6
        toggleHint.translatesAutoresizingMaskIntoConstraints = false
        configureShortcutHintLabel(toggleHint, theme: theme)

        let activeToggle = ClosureButton(handler: actions.toggleActiveTasks)
        activeToggle.image = NSImage(
            systemSymbolName: configuration.showsActiveTasks ? "bolt.fill" : "bolt.slash",
            accessibilityDescription: configuration.showsActiveTasks
                ? "Hide active tasks"
                : "Show active tasks"
        )
        activeToggle.contentTintColor = configuration.showsActiveTasks
            ? theme.accent
            : theme.secondaryText
        activeToggle.title = GlobalHotKeys.activeTasksShortcutLabel()
        activeToggle.imagePosition = .imageLeading
        activeToggle.imageHugsTitle = true
        activeToggle.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        activeToggle.toolTip = "\(configuration.showsActiveTasks ? "Hide" : "Show") active tasks — \(GlobalHotKeys.activeTasksShortcutLabel())"
        activeToggle.translatesAutoresizingMaskIntoConstraints = false

        let clear = ClosureButton(handler: actions.clearTasks)
        clear.title = "Clear"
        clear.font = theme.font(ofSize: 11, weight: .medium)
        clear.contentTintColor = theme.secondaryText
        clear.toolTip = "Dismiss all tasks"
        clear.alphaValue = 0
        clear.isHidden = configuration.completedTasks.isEmpty
        clear.translatesAutoresizingMaskIntoConstraints = false

        let settings = ClosureButton(handler: actions.openSettings)
        settings.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings"
        )
        settings.contentTintColor = theme.secondaryText
        settings.toolTip = "Appearance and connections"
        settings.alphaValue = 0
        settings.translatesAutoresizingMaskIntoConstraints = false

        let update = ClosureButton(handler: actions.installUpdate)
        update.image = NSImage(
            systemSymbolName: "arrow.down.circle.fill",
            accessibilityDescription: "Install Codex Notch update"
        )
        update.contentTintColor = theme.accent
        update.toolTip = configuration.updateVersion.map { "Install Codex Notch \($0)" }
        update.translatesAutoresizingMaskIntoConstraints = false
        update.isHidden = configuration.updateVersion == nil
        root.controls = [clear, settings]

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        var headerViews: [NSView] = [codexIcon, heading]
        let usageBadge: WeeklyUsageHeaderView?
        if configuration.usageState.isVisible {
            let badge = WeeklyUsageHeaderView(
                state: configuration.usageState,
                theme: theme,
                refresh: actions.refreshUsage
            )
            usageBadge = badge
            headerViews.append(badge)
        } else {
            usageBadge = nil
        }
        let statusBadge = HostStatusBadgeView(handler: actions.openConnections)
        statusBadge.update(configuration.hostHealth)
        headerViews.append(statusBadge)
        headerViews.append(contentsOf: [
            toggleHint,
            activeToggle,
            clear,
            update,
            settings,
        ])
        headerViews.forEach(header.addSubview)

        var headerConstraints = [
            header.heightAnchor.constraint(equalToConstant: menuBarHeaderHeight),
            codexIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 13),
            codexIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            codexIcon.widthAnchor.constraint(equalToConstant: 16),
            codexIcon.heightAnchor.constraint(equalToConstant: 16),
            heading.leadingAnchor.constraint(equalTo: codexIcon.trailingAnchor, constant: 8),
            heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
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
        if let usageBadge {
            headerConstraints.append(contentsOf: [
                usageBadge.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 12),
                usageBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                statusBadge.leadingAnchor.constraint(equalTo: usageBadge.trailingAnchor, constant: 7),
            ])
        } else {
            headerConstraints.append(
                statusBadge.leadingAnchor.constraint(equalTo: heading.trailingAnchor, constant: 12)
            )
        }
        headerConstraints.append(contentsOf: [
            statusBadge.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.leadingAnchor.constraint(
                greaterThanOrEqualTo: statusBadge.trailingAnchor,
                constant: 8
            ),
        ])
        if let exclusion = configuration.notchExclusion {
            let notchGuide = NSLayoutGuide()
            header.addLayoutGuide(notchGuide)
            let notchCenter = (exclusion.lowerBound + exclusion.upperBound) / 2
            headerConstraints.append(contentsOf: [
                notchGuide.centerXAnchor.constraint(
                    equalTo: header.centerXAnchor,
                    constant: notchCenter
                ),
                notchGuide.widthAnchor.constraint(
                    equalToConstant: exclusion.upperBound - exclusion.lowerBound
                ),
                statusBadge.trailingAnchor.constraint(
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

        let activeSection = addActiveTasks(
            configuration.displayedActiveTasks,
            totalCount: configuration.totalActiveTaskCount,
            shortcutLettersVisible: configuration.shortcutLettersVisible,
            theme: theme,
            to: stack,
            open: actions.openActiveTask
        )
        if !configuration.completedTasks.isEmpty
            && !configuration.displayedActiveTasks.isEmpty {
            let section = NSTextField(labelWithString: "COMPLETED")
            section.font = theme.font(ofSize: 9.5, weight: .bold)
            section.textColor = theme.tertiaryText
            section.translatesAutoresizingMaskIntoConstraints = false
            section.heightAnchor.constraint(equalToConstant: 20).isActive = true
            stack.addArrangedSubview(section)
        }

        var rows: [TaskRowView] = []
        var rowLookup: [String: TaskRowView] = [:]
        for (index, task) in configuration.completedTasks.enumerated() {
            let shortcutIndex = configuration.displayedActiveTasks.count + index
            let row = TaskRowView(
                task: task,
                index: shortcutIndex,
                theme: theme,
                now: configuration.now,
                isTriggered: task.eventID == configuration.triggeringEventID,
                shouldReduceMotion: configuration.shouldReduceMotion,
                open: { actions.openCompletedTask(task) },
                dismiss: { actions.dismissTask(shortcutIndex) }
            )
            if configuration.dismissingEventIDs.contains(task.eventID) {
                row.holdInvisibleForPendingDismissal()
            }
            row.setShortcutLetterVisible(configuration.shortcutLettersVisible)
            rows.append(row)
            rowLookup[task.eventID] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let emptyState: EmptyStateView?
        if configuration.completedTasks.isEmpty
            && configuration.displayedActiveTasks.isEmpty {
            let view = EmptyStateView(
                updateVersion: configuration.updateVersion,
                theme: theme
            )
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            emptyState = view
        } else {
            emptyState = nil
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
        root.onHoverChanged = actions.hoverChanged
        root.configureMotion(contentHost: stack, header: header, rows: rows)

        let activeHeight = configuration.displayedActiveTasks.isEmpty
            ? 0
            : 22 + configuration.displayedActiveTasks.count * 48
                + (configuration.totalActiveTaskCount
                    > configuration.displayedActiveTasks.count ? 24 : 0)
        let completedSectionHeight = !configuration.completedTasks.isEmpty
            && !configuration.displayedActiveTasks.isEmpty ? 20 : 0
        let contentHeight: CGFloat = configuration.completedTasks.isEmpty
            && configuration.displayedActiveTasks.isEmpty
            ? 168
            : 62 + CGFloat(
                configuration.completedTasks.count * 48
                    + activeHeight
                    + completedSectionHeight
            )
        let size = NSSize(
            width: geometry.windowWidth,
            height: contentHeight - reclaimedTopPadding
        )
        return BuiltOverlayContent(
            root: root,
            size: size,
            rowsByEventID: rowLookup,
            activeTaskRows: activeSection.rows,
            activeSectionLabel: activeSection.label,
            activeFreezeLabel: activeSection.freezeLabel,
            emptyStateView: emptyState,
            updateButton: update,
            settingsButton: settings,
            hostStatusBadge: statusBadge,
            weeklyUsageBadge: usageBadge,
            shortcutHintLabel: toggleHint
        )
    }

    private static func addActiveTasks(
        _ tasks: [ActiveTask],
        totalCount: Int,
        shortcutLettersVisible: Bool,
        theme: NotchTheme,
        to stack: NSStackView,
        open: @escaping (ActiveTask) -> Void
    ) -> (
        rows: [ActiveTaskRowView],
        label: NSTextField?,
        freezeLabel: NSTextField?
    ) {
        guard !tasks.isEmpty else { return ([], nil, nil) }

        let section = NSTextField(labelWithString: "ACTIVE")
        section.font = theme.font(ofSize: 9.5, weight: .bold)
        section.textColor = theme.tertiaryText
        section.translatesAutoresizingMaskIntoConstraints = false
        let frozen = NSTextField(labelWithString: "· FROZEN")
        frozen.font = theme.font(ofSize: 9.5, weight: .bold)
        frozen.textColor = theme.accent
        frozen.toolTip = "Live updates pause while you hold Control–Shift so task shortcuts stay stable. Release the keys to resume."
        frozen.setAccessibilityLabel("Active tasks frozen")
        frozen.setAccessibilityValue(
            "Live updates resume when Control and Shift are released"
        )
        frozen.isHidden = !shortcutLettersVisible
        frozen.translatesAutoresizingMaskIntoConstraints = false

        let sectionHost = NSView()
        sectionHost.translatesAutoresizingMaskIntoConstraints = false
        sectionHost.addSubview(section)
        sectionHost.addSubview(frozen)
        NSLayoutConstraint.activate([
            sectionHost.heightAnchor.constraint(equalToConstant: 22),
            section.leadingAnchor.constraint(equalTo: sectionHost.leadingAnchor, constant: 14),
            section.bottomAnchor.constraint(equalTo: sectionHost.bottomAnchor, constant: -3),
            frozen.leadingAnchor.constraint(equalTo: section.trailingAnchor, constant: 5),
            frozen.centerYAnchor.constraint(equalTo: section.centerYAnchor),
            frozen.trailingAnchor.constraint(
                lessThanOrEqualTo: sectionHost.trailingAnchor,
                constant: -14
            ),
        ])
        stack.addArrangedSubview(sectionHost)
        sectionHost.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let rows = tasks.enumerated().map { index, task in
            let row = ActiveTaskRowView(
                task: task,
                index: index,
                theme: theme,
                open: { open(task) }
            )
            row.setShortcutLetterVisible(shortcutLettersVisible)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return row
        }
        if totalCount > tasks.count {
            let remaining = NSTextField(
                labelWithString: "+ \(totalCount - tasks.count) more active tasks"
            )
            remaining.font = theme.font(ofSize: 10.5, weight: .medium)
            remaining.textColor = theme.secondaryText
            remaining.alignment = .center
            remaining.translatesAutoresizingMaskIntoConstraints = false
            remaining.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(remaining)
            remaining.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return (rows, section, frozen)
    }

    private static func configureShortcutHintLabel(
        _ label: NSTextField,
        theme: NotchTheme
    ) {
        label.stringValue = GlobalHotKeys.toggleShortcutLabel()
        label.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = theme.secondaryText
        label.layer?.backgroundColor = NSColor.clear.cgColor
        label.toolTip = "Show or hide Codex Notch"
        label.setAccessibilityLabel("Toggle Codex Notch")
        label.setAccessibilityValue(GlobalHotKeys.toggleShortcutLabel())
    }
}
