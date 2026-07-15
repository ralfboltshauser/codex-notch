import AppKit
import CodexNotchCore
import QuartzCore

final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifiers.remove(.capsLock)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsNavigationButton: ClosureButton {
    static let horizontalContentPadding: CGFloat = 12

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += Self.horizontalContentPadding * 2
        return size
    }
}

final class RemoteConnectionRowView: NSView {
    private let indicator = NSImageView()
    private let status = NSTextField(labelWithString: "")
    private let statusDetail = NSTextField(labelWithString: "")

    init(host: RemoteHost, remove: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = ThemeStore.shared.activeTheme.quietSurface.cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        indicator.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: host.label)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = ThemeStore.shared.activeTheme.primaryText
        name.lineBreakMode = .byTruncatingTail

        let alias = NSTextField(labelWithString: host.sshAlias)
        alias.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        alias.textColor = ThemeStore.shared.activeTheme.tertiaryText
        alias.lineBreakMode = .byTruncatingTail

        let identity = NSStackView(views: [name, alias])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2
        identity.translatesAutoresizingMaskIntoConstraints = false
        identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        status.font = .systemFont(ofSize: 11, weight: .semibold)
        status.alignment = .right
        status.lineBreakMode = .byTruncatingTail
        statusDetail.font = .systemFont(ofSize: 10, weight: .regular)
        statusDetail.textColor = ThemeStore.shared.activeTheme.tertiaryText
        statusDetail.alignment = .right
        statusDetail.lineBreakMode = .byTruncatingMiddle
        let health = NSStackView(views: [status, statusDetail])
        health.orientation = .vertical
        health.alignment = .trailing
        health.spacing = 2
        health.translatesAutoresizingMaskIntoConstraints = false
        health.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let removeButton = ClosureButton(handler: remove)
        removeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Remove \(host.label)"
        )
        removeButton.contentTintColor = ThemeStore.shared.activeTheme.secondaryText
        removeButton.toolTip = "Remove \(host.label)"
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        [indicator, identity, health, removeButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 18),
            indicator.heightAnchor.constraint(equalToConstant: 18),
            identity.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 10),
            identity.centerYAnchor.constraint(equalTo: centerYAnchor),
            identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            health.leadingAnchor.constraint(greaterThanOrEqualTo: identity.trailingAnchor, constant: 12),
            health.centerYAnchor.constraint(equalTo: centerYAnchor),
            health.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
            removeButton.leadingAnchor.constraint(equalTo: health.trailingAnchor, constant: 8),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 28),
            removeButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(health: RemoteHostHealth, refreshing: Bool) {
        let symbol: String
        let color: NSColor
        switch health {
        case .checking:
            symbol = "ellipsis.circle.fill"
            color = ThemeStore.shared.activeTheme.tertiaryText
        case .working:
            symbol = "checkmark.circle.fill"
            color = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        case .unreachable:
            symbol = "wifi.slash"
            color = .systemRed
        case .needsAttention:
            symbol = "exclamationmark.triangle.fill"
            color = .systemOrange
        }
        indicator.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: health.statusText
        )
        indicator.contentTintColor = color
        status.stringValue = health.statusText
        status.textColor = color

        if refreshing, health.checkedAt != nil {
            statusDetail.stringValue = "Rechecking…"
        } else if let detail = health.detailText {
            statusDetail.stringValue = detail
        } else if health.checkedAt != nil {
            statusDetail.stringValue = "Checked just now"
        } else {
            statusDetail.stringValue = "End-to-end test"
        }
        statusDetail.toolTip = health.detailText
        toolTip = health.detailText
        setAccessibilityLabel("\(health.statusText). \(statusDetail.stringValue)")
    }
}

final class FlippedHostStackView: NSStackView {
    override var isFlipped: Bool { true }

    init(arrangedViews: [NSView]) {
        super.init(frame: .zero)
        arrangedViews.forEach(addArrangedSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class OnboardingWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    static let completionKey = "onboardingComplete.v2"

    private enum SettingsPage {
        case appearance
        case tasks
        case sounds
        case connections
    }

    static func versionDescription(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> String {
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unavailable"
        }
    }

    private let pairings: PairingStore
    private let pairer: RemoteHostPairer
    private let notificationSounds: NotificationSoundPlayer
    private let doNotDisturbPreferences: DoNotDisturbPreferences
    private let isHookInstalled: () -> Bool
    private let shouldReduceMotion: () -> Bool
    private let root = ThemeBackdropView()
    private let content = NSView()
    private let hostField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var remoteHealth = RemoteHostHealthSnapshot.empty
    private var remoteRows: [String: RemoteConnectionRowView] = [:]
    private weak var remoteSummaryLabel: NSTextField?
    private weak var remoteRefreshButton: ClosureButton?
    private weak var checkForUpdatesButton: ClosureButton?
    private weak var doNotDisturbButton: ClosureButton?
    private var working = false
    private var contentTransitionID = 0
    private var selectedPage: SettingsPage = .appearance
    private var themeCards: [ThemeCardButton] = []
    private var soundCards: [NotificationSoundCardButton] = []
    private var settingsTabs: [SettingsNavigationButton] = []

    var onConnectionsChanged: (() -> Void)?
    var onRefreshConnections: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onUninstall: ((@escaping (Result<Void, Error>) -> Void) -> Void)?

    var checkForUpdatesButtonForTesting: NSButton? { checkForUpdatesButton }
    var doNotDisturbButtonForTesting: NSButton? { doNotDisturbButton }
    var settingsTabTitlesForTesting: [String] { settingsTabs.map(\.title) }
    var renderedThemeChoiceCountForTesting: Int { themeCards.count }
    var renderedSoundChoiceCountForTesting: Int { soundCards.count }
    var renderedThemeChoiceFramesForTesting: [NSRect] {
        root.layoutSubtreeIfNeeded()
        return themeCards.map { $0.convert($0.bounds, to: root) }
    }
    var renderedSoundChoiceFramesForTesting: [NSRect] {
        root.layoutSubtreeIfNeeded()
        return soundCards.map { $0.convert($0.bounds, to: root) }
    }
    var settingsBoundsForTesting: NSRect {
        root.layoutSubtreeIfNeeded()
        return root.bounds
    }

    func showSoundsForTesting() {
        buildSettingsPage(.sounds)
    }

    func showTasksForTesting() {
        buildSettingsPage(.tasks)
    }

    func selectTasksTabForTesting() {
        settingsTabs.first(where: { $0.title == "Tasks" })?.performClick(nil)
    }

    init(
        pairings: PairingStore,
        pairer: RemoteHostPairer,
        notificationSounds: NotificationSoundPlayer = NotificationSoundPlayer(),
        doNotDisturbPreferences: DoNotDisturbPreferences = .shared,
        isHookInstalled: @escaping () -> Bool = { CodexHookInstaller().isInstalled },
        shouldReduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        self.pairings = pairings
        self.pairer = pairer
        self.notificationSounds = notificationSounds
        self.doNotDisturbPreferences = doNotDisturbPreferences
        self.isHookInstalled = isHookInstalled
        self.shouldReduceMotion = shouldReduceMotion
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 650),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Notch Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        super.init(window: window)
        window.delegate = self

        window.contentView = root
        showAppropriateStep()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        ThemeStore.shared.endPreview()
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
    }

    func present() {
        showAppropriateStep()
        window?.center()
        ApplicationMenu.install()
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateRemoteHealth(_ snapshot: RemoteHostHealthSnapshot) {
        remoteHealth = snapshot
        remoteSummaryLabel?.stringValue = snapshot.hosts.isEmpty
            ? "NONE CONFIGURED"
            : snapshot.summaryText.uppercased()
        remoteSummaryLabel?.textColor = snapshot.problemCount > 0
            ? .systemOrange
            : ThemeStore.shared.activeTheme.tertiaryText
        remoteRefreshButton?.isEnabled = !snapshot.isRefreshing && !snapshot.hosts.isEmpty
        remoteRefreshButton?.toolTip = snapshot.isRefreshing
            ? "Checking remote hosts…"
            : "Check remote hosts now"
        for host in snapshot.hosts {
            remoteRows[host.id]?.update(
                health: snapshot.health(for: host),
                refreshing: snapshot.isRefreshing
            )
        }
    }

    private func showAppropriateStep() {
        if isHookInstalled() {
            buildSettingsPage(selectedPage)
        } else {
            buildLocalSetup()
        }
    }

    private func resetContent() {
        content.removeFromSuperview()
        content.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.removeAllAnimations()
        content.layer?.opacity = 1
        content.layer?.transform = CATransform3DIdentity
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 42),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -42),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -32),
        ])
    }

    private func buildSettingsPage(_ page: SettingsPage) {
        selectedPage = page
        ThemeStore.shared.endPreview()
        switch page {
        case .appearance: buildAppearance()
        case .tasks: buildTasks()
        case .sounds: buildSounds()
        case .connections: buildConnections()
        }
    }

    private func buildTasks() {
        resetContent()
        let theme = ThemeStore.shared.activeTheme
        let activeTaskPreferences = ActiveTaskPreferences.shared
        let header = settingsHeader(selected: .tasks)
        let title = makeLabel("Task behavior", size: 25, weight: .semibold, color: theme.primaryText)
        let subtitle = makeLabel(
            "Choose what the notch shows and when it appears.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText
        )

        func preferenceRow(
            symbol: String,
            accessibilityDescription: String,
            title: String,
            detail: String,
            enabled: Bool,
            toolTip: String,
            action: @escaping () -> Void
        ) -> (NSView, ClosureButton) {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false
            let icon = NSImageView(image: NSImage(
                systemSymbolName: symbol,
                accessibilityDescription: accessibilityDescription
            ) ?? NSImage())
            icon.contentTintColor = theme.accent
            icon.translatesAutoresizingMaskIntoConstraints = false
            let label = makeLabel(title, size: 14, weight: .semibold, color: theme.primaryText)
            let detailLabel = makeLabel(
                detail,
                size: 11.5,
                weight: .regular,
                color: theme.secondaryText
            )
            detailLabel.maximumNumberOfLines = 2
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
            return (row, toggle)
        }

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.quietSurface.cgColor
        card.layer?.borderColor = theme.border.cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        let activeTaskRow = preferenceRow(
            symbol: "bolt.horizontal.circle.fill",
            accessibilityDescription: "Active tasks",
            title: "Show active tasks",
            detail: "Live state is kept in memory only. Prompts, output, paths, and transcripts are never sent to the notch.",
            enabled: activeTaskPreferences.isVisible,
            toolTip: "Toggle active tasks"
        ) { [weak self] in
            _ = ActiveTaskPreferences.shared.toggle()
            self?.buildTasks()
        }
        let doNotDisturbRow = preferenceRow(
            symbol: "moon.fill",
            accessibilityDescription: "Do Not Disturb",
            title: "Do Not Disturb",
            detail: "Stops automatic openings for finished tasks and updates. Manual shortcuts and sounds still work; macOS Focus is not used.",
            enabled: doNotDisturbPreferences.isEnabled,
            toolTip: "Toggle Do Not Disturb"
        ) { [weak self] in
            guard let self else { return }
            _ = self.doNotDisturbPreferences.toggle()
            self.buildTasks()
        }
        doNotDisturbButton = doNotDisturbRow.1
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.border.cgColor
        [activeTaskRow.0, divider, doNotDisturbRow.0].forEach(card.addSubview)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 177),
            activeTaskRow.0.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            activeTaskRow.0.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            activeTaskRow.0.topAnchor.constraint(equalTo: card.topAnchor),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: activeTaskRow.0.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            doNotDisturbRow.0.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            doNotDisturbRow.0.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            doNotDisturbRow.0.topAnchor.constraint(equalTo: divider.bottomAnchor),
            doNotDisturbRow.0.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        let shortcutTitle = makeLabel("QUICK TOGGLE", size: 10, weight: .bold, color: theme.tertiaryText)
        let shortcutCard = NSView()
        shortcutCard.translatesAutoresizingMaskIntoConstraints = false
        shortcutCard.wantsLayer = true
        shortcutCard.layer?.backgroundColor = theme.surface.cgColor
        shortcutCard.layer?.cornerRadius = 12
        shortcutCard.layer?.cornerCurve = .continuous
        let shortcutDetail = makeLabel("Show or hide active tasks from anywhere", size: 13, weight: .medium, color: theme.primaryText)
        let keys = makeLabel(GlobalHotKeys.activeTasksShortcutLabel(), size: 12, weight: .semibold, color: theme.accent)
        keys.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        [shortcutDetail, keys].forEach(shortcutCard.addSubview)
        NSLayoutConstraint.activate([
            shortcutCard.heightAnchor.constraint(equalToConstant: 58),
            shortcutDetail.leadingAnchor.constraint(equalTo: shortcutCard.leadingAnchor, constant: 16),
            shortcutDetail.centerYAnchor.constraint(equalTo: shortcutCard.centerYAnchor),
            keys.trailingAnchor.constraint(equalTo: shortcutCard.trailingAnchor, constant: -16),
            keys.centerYAnchor.constraint(equalTo: shortcutCard.centerYAnchor),
        ])
        let note = makeLabel(
            "Finished tasks are still collected in Do Not Disturb and remain available with \(GlobalHotKeys.toggleShortcutLabel()).",
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText
        )
        note.maximumNumberOfLines = 2
        let done = ClosureButton { [weak self] in self?.close() }
        done.title = "Done"
        styleSecondaryButton(done)
        let checkForUpdates = makeCheckForUpdatesButton()
        let footer = NSStackView(views: [makeVersionLabel(), checkForUpdates, NSView(), done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        let stack = NSStackView(views: [header, title, subtitle, card, shortcutTitle, shortcutCard, note, footer])
        configureStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(26, after: card)
        stack.setCustomSpacing(9, after: shortcutTitle)
        stack.setCustomSpacing(20, after: shortcutCard)
        stack.setCustomSpacing(30, after: note)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func buildAppearance() {
        resetContent()
        themeCards.removeAll()
        let theme = ThemeStore.shared.activeTheme
        let header = settingsHeader(selected: .appearance)
        let title = makeLabel("Make it yours", size: 25, weight: .semibold, color: theme.primaryText)
        let subtitle = makeLabel(
            "A theme changes the notch, its feedback, and this space together.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText
        )
        let preview = NotchThemePreviewView()

        let sectionTitle = makeLabel(
            "THEMES",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText
        )
        let hint = makeLabel(
            "Hover to try one live · Click to keep it",
            size: 11,
            weight: .medium,
            color: theme.secondaryText
        )
        let sectionHeader = NSStackView(views: [sectionTitle, NSView(), hint])
        sectionHeader.orientation = .horizontal
        sectionHeader.alignment = .centerY

        let cards = NotchTheme.all.map { palette -> ThemeCardButton in
            let card = ThemeCardButton(theme: palette)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.setSelected(palette.id == ThemeStore.shared.selectedID)
            card.onSelect = { [weak self] id in
                ThemeStore.shared.select(id)
                self?.themeCards.forEach {
                    $0.setSelected($0.theme.id == ThemeStore.shared.selectedID)
                }
            }
            themeCards.append(card)
            return card
        }
        let firstRow = themeCardRow(Array(cards[0..<3]))
        let secondRow = themeCardRow(Array(cards[3..<6]))
        let grid = NSStackView(views: [firstRow, secondRow])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 10
        grid.distribution = .fillEqually
        NSLayoutConstraint.activate([
            firstRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
            secondRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])

        let done = ClosureButton { [weak self] in self?.close() }
        done.title = "Done"
        styleSecondaryButton(done)
        let checkForUpdates = makeCheckForUpdatesButton()
        let footer = NSStackView(views: [makeVersionLabel(), checkForUpdates, NSView(), done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let stack = NSStackView(views: [header, title, subtitle, preview, sectionHeader, grid, footer])
        configureStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(20, after: preview)
        stack.setCustomSpacing(9, after: sectionHeader)
        stack.setCustomSpacing(18, after: grid)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 142),
            sectionHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.heightAnchor.constraint(equalToConstant: 196),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func buildSounds() {
        resetContent()
        soundCards.removeAll()
        let theme = ThemeStore.shared.activeTheme
        let selected = notificationSounds.selectedSound
        let header = settingsHeader(selected: .sounds)
        let title = makeLabel("A finish worth hearing", size: 25, weight: .semibold, color: theme.primaryText)
        let subtitle = makeLabel(
            "Six short completion tones, designed to stay satisfying even on a busy day.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText
        )
        let sectionTitle = makeLabel(
            "COMPLETION TONE",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText
        )
        let hint = makeLabel(
            "Click any sound to preview it",
            size: 11,
            weight: .medium,
            color: theme.secondaryText
        )
        let sectionHeader = NSStackView(views: [sectionTitle, NSView(), hint])
        sectionHeader.orientation = .horizontal
        sectionHeader.alignment = .centerY

        let audibleCards = NotificationSound.allCases
            .filter { $0 != .none }
            .map { sound -> NotificationSoundCardButton in
                let card = NotificationSoundCardButton(sound: sound, theme: theme)
                card.translatesAutoresizingMaskIntoConstraints = false
                card.setSelected(sound == selected)
                card.onSelect = { [weak self] sound in
                    self?.notificationSounds.selectAndPreview(sound)
                    self?.buildSounds()
                }
                return card
            }
        let firstRow = soundCardRow(Array(audibleCards[0..<3]))
        let secondRow = soundCardRow(Array(audibleCards[3..<6]))
        let grid = NSStackView(views: [firstRow, secondRow])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 10
        grid.distribution = .fillEqually
        NSLayoutConstraint.activate([
            firstRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
            secondRow.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])

        let silent = NotificationSoundCardButton(sound: .none, theme: theme)
        silent.translatesAutoresizingMaskIntoConstraints = false
        silent.setSelected(selected == .none)
        silent.onSelect = { [weak self] sound in
            self?.notificationSounds.selectAndPreview(sound)
            self?.buildSounds()
        }
        soundCards = audibleCards + [silent]

        let contextIcon = NSImageView(image: NSImage(
            systemSymbolName: "bell.badge.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        contextIcon.contentTintColor = theme.accent
        contextIcon.translatesAutoresizingMaskIntoConstraints = false
        let context = makeLabel(
            "Sounds play only for newly accepted local or remote Stop-hook events. Opening the notch yourself stays quiet.",
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText
        )
        context.maximumNumberOfLines = 2
        let contextRow = NSStackView(views: [contextIcon, context])
        contextRow.orientation = .horizontal
        contextRow.alignment = .centerY
        contextRow.spacing = 10
        contextRow.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        contextRow.wantsLayer = true
        contextRow.layer?.backgroundColor = theme.quietSurface.cgColor
        contextRow.layer?.cornerRadius = 10
        contextRow.layer?.cornerCurve = .continuous

        let done = ClosureButton { [weak self] in self?.close() }
        done.title = "Done"
        styleSecondaryButton(done)
        let checkForUpdates = makeCheckForUpdatesButton()
        let footer = NSStackView(views: [makeVersionLabel(), checkForUpdates, NSView(), done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let stack = NSStackView(
            views: [header, title, subtitle, sectionHeader, grid, silent, contextRow, footer]
        )
        configureStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(27, after: subtitle)
        stack.setCustomSpacing(9, after: sectionHeader)
        stack.setCustomSpacing(10, after: grid)
        stack.setCustomSpacing(18, after: silent)
        stack.setCustomSpacing(20, after: contextRow)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sectionHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.heightAnchor.constraint(equalToConstant: 154),
            silent.widthAnchor.constraint(equalTo: stack.widthAnchor),
            silent.heightAnchor.constraint(equalToConstant: 58),
            contextRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            contextIcon.widthAnchor.constraint(equalToConstant: 18),
            contextIcon.heightAnchor.constraint(equalToConstant: 18),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func soundCardRow(_ cards: [NotificationSoundCardButton]) -> NSStackView {
        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        NSLayoutConstraint.activate(cards.map {
            $0.heightAnchor.constraint(equalToConstant: 72)
        })
        return row
    }

    private func themeCardRow(_ cards: [ThemeCardButton]) -> NSStackView {
        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        NSLayoutConstraint.activate(cards.map {
            $0.heightAnchor.constraint(equalToConstant: 93)
        })
        return row
    }

    private func settingsHeader(selected: SettingsPage) -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let mark = NSImageView(image: NSImage(
            systemSymbolName: "sparkles.rectangle.stack.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        mark.contentTintColor = theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        let product = makeLabel("Codex Notch", size: 14, weight: .semibold, color: theme.primaryText)
        let spacer = NSView()

        let appearance = settingsNavigationButton(
            title: "Themes",
            symbol: "paintpalette.fill",
            active: selected == .appearance
        ) { [weak self] in self?.transitionContent { self?.buildSettingsPage(.appearance) } }
        let sounds = settingsNavigationButton(
            title: "Sounds",
            symbol: "waveform",
            active: selected == .sounds
        ) { [weak self] in self?.transitionContent { self?.buildSettingsPage(.sounds) } }
        let tasks = settingsNavigationButton(
            title: "Tasks",
            symbol: "bolt.fill",
            active: selected == .tasks
        ) { [weak self] in self?.transitionContent { self?.buildSettingsPage(.tasks) } }
        let connections = settingsNavigationButton(
            title: "Connections",
            symbol: "point.3.connected.trianglepath.dotted",
            active: selected == .connections
        ) { [weak self] in self?.transitionContent { self?.buildSettingsPage(.connections) } }
        let navigation = NSStackView(views: [appearance, tasks, sounds, connections])
        navigation.orientation = .horizontal
        navigation.spacing = 6
        navigation.alignment = .centerY
        settingsTabs = [appearance, tasks, sounds, connections]

        let header = NSStackView(views: [mark, product, spacer, navigation])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 32),
            mark.widthAnchor.constraint(equalToConstant: 19),
            mark.heightAnchor.constraint(equalToConstant: 19),
            appearance.heightAnchor.constraint(equalToConstant: 30),
            tasks.heightAnchor.constraint(equalToConstant: 30),
            sounds.heightAnchor.constraint(equalToConstant: 30),
            connections.heightAnchor.constraint(equalToConstant: 30),
        ])
        return header
    }

    private func settingsNavigationButton(
        title: String,
        symbol: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> SettingsNavigationButton {
        let theme = ThemeStore.shared.activeTheme
        let button = SettingsNavigationButton(handler: action)
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .systemFont(ofSize: 11.5, weight: active ? .semibold : .medium)
        button.contentTintColor = active ? theme.primaryText : theme.secondaryText
        button.layer?.backgroundColor = (active ? theme.hoverSurface : NSColor.clear).cgColor
        button.layer?.cornerRadius = 9
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func transitionContent(to build: @escaping () -> Void) {
        guard window?.isVisible == true, let layer = content.layer else {
            build()
            return
        }
        contentTransitionID &+= 1
        let transitionID = contentTransitionID
        let reduceMotion = shouldReduceMotion()
        animateContent(
            layer: layer,
            opacity: 0,
            transform: reduceMotion
                ? CATransform3DIdentity
                : CATransform3DMakeTranslation(-8, 0, 0),
            duration: 0.10
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self, self.contentTransitionID == transitionID else { return }
            build()
            self.content.layoutSubtreeIfNeeded()
            guard let incomingLayer = self.content.layer else { return }
            let initialTransform = reduceMotion
                ? CATransform3DIdentity
                : CATransform3DMakeTranslation(10, 0, 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 0
            incomingLayer.transform = initialTransform
            CATransaction.commit()
            self.animateContent(
                layer: incomingLayer,
                opacity: 1,
                transform: CATransform3DIdentity,
                duration: reduceMotion ? NotchMotion.reducedMotionFadeDuration : 0.18
            )
        }
    }

    private func animateContent(
        layer: CALayer,
        opacity: Float,
        transform: CATransform3D,
        duration: TimeInterval
    ) {
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        layer.transform = transform
        CATransaction.commit()

        layer.removeAnimation(forKey: "settingsContent")
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
        layer.add(group, forKey: "settingsContent")
    }

    private func buildLocalSetup() {
        resetContent()
        let icon = makeIcon(symbol: "bolt.horizontal.circle.fill")
        let title = makeLabel("Codex Notch", size: 27, weight: .semibold, color: .white)
        let subtitle = makeLabel(
            "Keep completed tasks within reach without moving focus away from your work.",
            size: 14,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.52)
        )
        subtitle.maximumNumberOfLines = 2

        let install = ClosureButton { [weak self] in self?.installLocalHook() }
        install.title = "Install local completion hook"
        stylePrimaryButton(install)
        let uninstall = makeUninstallButton()
        let version = makeVersionLabel()
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(views: [icon, title, subtitle, install, statusLabel, uninstall, version])
        configureStack(stack)
        stack.setCustomSpacing(9, after: title)
        stack.setCustomSpacing(34, after: subtitle)
        stack.setCustomSpacing(8, after: uninstall)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            install.widthAnchor.constraint(equalTo: stack.widthAnchor),
            install.heightAnchor.constraint(equalToConstant: 42),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            uninstall.widthAnchor.constraint(equalToConstant: 172),
            uninstall.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func buildTrustStep() {
        resetContent()
        let icon = makeIcon(symbol: "checkmark.seal.fill")
        let title = makeLabel("Review the local hook", size: 25, weight: .semibold, color: .white)
        let subtitle = makeLabel(
            "Codex requires explicit trust before a new command hook can run.",
            size: 14,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.52)
        )

        let review = ClosureButton { [weak self] in
            do { try CodexHookTrustLauncher.openCLI() }
            catch { self?.setStatus(error.localizedDescription, error: true) }
        }
        review.title = "Open Codex hook review"
        styleSecondaryButton(review)

        let done = ClosureButton { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completionKey)
            self?.transitionContent { self?.buildSettingsPage(.appearance) }
        }
        done.title = "Hook trusted"
        stylePrimaryButton(done)
        let version = makeVersionLabel()

        let buttons = NSStackView(views: [review, done])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(views: [icon, title, subtitle, buttons, statusLabel, version])
        configureStack(stack)
        stack.setCustomSpacing(9, after: title)
        stack.setCustomSpacing(34, after: subtitle)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            review.heightAnchor.constraint(equalToConstant: 42),
            done.heightAnchor.constraint(equalToConstant: 42),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func buildConnections() {
        resetContent()
        let theme = ThemeStore.shared.activeTheme
        let header = settingsHeader(selected: .connections)
        let title = makeLabel("Connections", size: 25, weight: .semibold, color: theme.primaryText)
        let subtitle = makeLabel(
            "Choose where completed Codex tasks can reach this Mac.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText
        )
        let local = connectionRow(label: "This Mac", detail: "Local hook", removable: nil)

        let remoteTitle = makeLabel(
            "REMOTE UBUNTU HOSTS",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText
        )
        let remoteSummary = makeLabel(
            "",
            size: 9.5,
            weight: .semibold,
            color: theme.tertiaryText
        )
        remoteSummary.alignment = .right
        remoteSummary.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        remoteSummaryLabel = remoteSummary
        let refresh = ClosureButton { [weak self] in self?.onRefreshConnections?() }
        refresh.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Refresh remote host status"
        )
        refresh.contentTintColor = theme.secondaryText
        refresh.toolTip = "Check remote hosts now"
        refresh.translatesAutoresizingMaskIntoConstraints = false
        remoteRefreshButton = refresh
        let remoteHeader = NSStackView(
            views: [remoteTitle, NSView(), remoteSummary, refresh]
        )
        remoteHeader.orientation = .horizontal
        remoteHeader.alignment = .centerY
        remoteHeader.spacing = 8

        let configuredHosts = pairings.hosts.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        let displayedHealth = RemoteHostHealthSnapshot(
            hosts: configuredHosts,
            healthByHostID: remoteHealth.healthByHostID,
            isRefreshing: remoteHealth.isRefreshing
        )
        remoteHealth = displayedHealth
        remoteRows.removeAll()
        let hostRows = configuredHosts.map { host in
            let row = RemoteConnectionRowView(host: host) { [weak self] in
                self?.remove(host)
            }
            row.update(
                health: displayedHealth.health(for: host),
                refreshing: displayedHealth.isRefreshing
            )
            remoteRows[host.id] = row
            return row
        }
        let hostViews: [NSView] = hostRows.isEmpty ? [emptyHostsLabel()] : hostRows
        let hostList = FlippedHostStackView(arrangedViews: hostViews)
        hostList.orientation = .vertical
        hostList.spacing = 7
        hostList.alignment = .leading
        let listContentHeight = hostRows.isEmpty
            ? CGFloat(32)
            : CGFloat(hostRows.count * 56 + max(0, hostRows.count - 1) * 7)
        hostList.frame = NSRect(x: 0, y: 0, width: 636, height: listContentHeight)
        hostList.autoresizingMask = [.width]
        hostRows.forEach {
            $0.widthAnchor.constraint(equalTo: hostList.widthAnchor).isActive = true
        }

        let hostScroll = NSScrollView()
        hostScroll.drawsBackground = false
        hostScroll.hasHorizontalScroller = false
        hostScroll.hasVerticalScroller = hostRows.count > 3
        hostScroll.autohidesScrollers = true
        hostScroll.scrollerStyle = .overlay
        hostScroll.documentView = hostList
        hostScroll.translatesAutoresizingMaskIntoConstraints = false

        hostField.placeholderString = "SSH host alias"
        hostField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hostField.textColor = theme.primaryText
        hostField.backgroundColor = theme.quietSurface
        hostField.isBezeled = true
        hostField.bezelStyle = .roundedBezel
        hostField.focusRingType = .none
        hostField.delegate = self
        hostField.translatesAutoresizingMaskIntoConstraints = false

        let pair = ClosureButton { [weak self] in self?.pairRemoteHost() }
        pair.title = "Pair"
        stylePrimaryButton(pair)
        let pairRow = NSStackView(views: [hostField, pair])
        pairRow.orientation = .horizontal
        pairRow.spacing = 10

        let done = ClosureButton { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completionKey)
            self?.close()
        }
        done.title = "Done"
        styleSecondaryButton(done)

        let uninstall = makeUninstallButton()
        let spacer = NSView()
        let version = makeVersionLabel()
        let checkForUpdates = makeCheckForUpdatesButton()
        let footer = NSStackView(views: [uninstall, spacer, version, checkForUpdates, done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(
            views: [header, title, subtitle, local, remoteHeader, hostScroll, pairRow, statusLabel, footer]
        )
        configureStack(stack)
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(28, after: local)
        stack.setCustomSpacing(8, after: remoteHeader)
        stack.setCustomSpacing(18, after: hostScroll)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            local.widthAnchor.constraint(equalTo: stack.widthAnchor),
            remoteHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            refresh.widthAnchor.constraint(equalToConstant: 26),
            refresh.heightAnchor.constraint(equalToConstant: 26),
            hostScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostScroll.heightAnchor.constraint(equalToConstant: min(listContentHeight, 182)),
            pairRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostField.heightAnchor.constraint(equalToConstant: 40),
            pair.widthAnchor.constraint(equalToConstant: 92),
            pair.heightAnchor.constraint(equalToConstant: 40),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            uninstall.widthAnchor.constraint(equalToConstant: 172),
            uninstall.heightAnchor.constraint(equalToConstant: 40),
            checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
        updateRemoteHealth(displayedHealth)
    }

    private func confirmUninstall() {
        guard !working else { return }
        let hostCount = pairings.hosts.count
        let remoteDescription = hostCount == 0
            ? "There are no paired remote hosts."
            : "This also connects to and cleans \(hostCount) paired remote host\(hostCount == 1 ? "" : "s"); they must be reachable."
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Codex Notch?"
        alert.informativeText = "\(remoteDescription) The local hook, hook backups, retry services, queued completions, credentials, settings, and this app will be removed. Other Codex hooks are preserved."
        alert.addButton(withTitle: "Uninstall Everywhere")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.beginUninstall()
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func beginUninstall() {
        guard !working else { return }
        guard let onUninstall else {
            setStatus("The uninstall service is unavailable.", error: true)
            return
        }
        working = true
        let hostCount = pairings.hosts.count
        setStatus(
            hostCount == 0 ? "Cleaning this Mac…" : "Cleaning \(hostCount) remote host\(hostCount == 1 ? "" : "s") first…",
            error: false
        )
        onUninstall { [weak self] result in
            guard let self else { return }
            self.working = false
            switch result {
            case .success:
                self.setStatus("Cleanup complete. Closing Codex Notch…", error: false)
            case .failure(let error):
                self.onConnectionsChanged?()
                self.transitionContent {
                    self.buildConnections()
                    self.setStatus(error.localizedDescription, error: true)
                }
            }
        }
    }

    private func installLocalHook() {
        do {
            try CodexHookInstaller().install()
            UserDefaults.standard.set(false, forKey: Self.completionKey)
            transitionContent { [weak self] in self?.buildTrustStep() }
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func pairRemoteHost() {
        guard !working else { return }
        let alias = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { setStatus("Enter an SSH host alias.", error: true); return }
        working = true
        setStatus("Pairing \(alias)…", error: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let host = try self.pairer.pair(sshAlias: alias)
                DispatchQueue.main.async {
                    self.working = false
                    self.onConnectionsChanged?()
                    self.transitionContent { [weak self] in self?.buildConnections() }
                    try? self.pairer.openTrustReview(for: host)
                }
            } catch {
                DispatchQueue.main.async {
                    self.working = false
                    self.setStatus(error.localizedDescription, error: true)
                }
            }
        }
    }

    private func remove(_ host: RemoteHost) {
        guard !working else { return }
        working = true
        setStatus("Removing \(host.label)…", error: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.pairer.unpair(host)
                DispatchQueue.main.async {
                    self.working = false
                    self.onConnectionsChanged?()
                    self.transitionContent { [weak self] in self?.buildConnections() }
                }
            } catch {
                DispatchQueue.main.async {
                    self.working = false
                    self.setStatus(error.localizedDescription, error: true)
                }
            }
        }
    }

    private func connectionRow(label: String, detail: String, removable: (() -> Void)?) -> NSView {
        let theme = ThemeStore.shared.activeTheme
        let indicator = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        indicator.contentTintColor = theme.accent
        let name = makeLabel(label, size: 13, weight: .semibold, color: theme.primaryText)
        let secondary = makeLabel(detail, size: 11, weight: .regular, color: theme.secondaryText)
        let text = NSStackView(views: [name, secondary])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let spacer = NSView()
        var views: [NSView] = [indicator, text, spacer]
        if let removable {
            let remove = ClosureButton(handler: removable)
            remove.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")
            remove.isBordered = false
            remove.contentTintColor = theme.secondaryText
            views.append(remove)
            NSLayoutConstraint.activate([
                remove.widthAnchor.constraint(equalToConstant: 28),
                remove.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.wantsLayer = true
        row.layer?.backgroundColor = theme.quietSurface.cgColor
        row.layer?.cornerRadius = 10
        row.layer?.cornerCurve = .continuous
        row.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 52),
            indicator.widthAnchor.constraint(equalToConstant: 18),
            indicator.heightAnchor.constraint(equalToConstant: 18),
        ])
        return row
    }

    private func emptyHostsLabel() -> NSView {
        let label = makeLabel(
            "No remote hosts paired",
            size: 12,
            weight: .regular,
            color: ThemeStore.shared.activeTheme.tertiaryText
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func setStatus(_ text: String, error: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = error ? .systemRed : NSColor.white.withAlphaComponent(0.45)
    }

    private func configureStatusLabel() {
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureStack(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeIcon(symbol: String) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        view.contentTintColor = ThemeStore.shared.activeTheme.accent
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func makeVersionLabel() -> NSTextField {
        let label = makeLabel(
            Self.versionDescription(),
            size: 11,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.34)
        )
        label.toolTip = "Installed Codex Notch version"
        return label
    }

    private func makeCheckForUpdatesButton() -> ClosureButton {
        let button = ClosureButton { [weak self] in
            self?.onCheckForUpdates?()
        }
        button.title = "Check for Updates"
        button.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Check for Codex Notch updates"
        )
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.toolTip = "Check for a newer version of Codex Notch"
        styleSecondaryButton(button)
        checkForUpdatesButton = button
        return button
    }

    private func stylePrimaryButton(_ button: ClosureButton) {
        let theme = ThemeStore.shared.activeTheme
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .black
        button.wantsLayer = true
        button.layer?.backgroundColor = theme.accent.cgColor
        button.layer?.cornerRadius = 9
        button.layer?.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func styleSecondaryButton(_ button: ClosureButton) {
        let theme = ThemeStore.shared.activeTheme
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.contentTintColor = theme.primaryText
        button.wantsLayer = true
        button.layer?.backgroundColor = theme.quietSurface.cgColor
        button.layer?.cornerRadius = 9
        button.layer?.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func styleDestructiveButton(_ button: ClosureButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.contentTintColor = NSColor.systemRed.withAlphaComponent(0.9)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor
        button.layer?.cornerRadius = 7
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeUninstallButton() -> ClosureButton {
        let button = ClosureButton { [weak self] in self?.confirmUninstall() }
        button.title = "Uninstall Codex Notch…"
        styleDestructiveButton(button)
        return button
    }
}
