import AppKit

final class ConnectionSettingsPageView: NSView {
    let displayedHealth: RemoteHostHealthSnapshot
    let remoteRows: [String: RemoteConnectionRowView]
    let remoteSummaryLabel: NSTextField
    let remoteRefreshButton: ClosureButton
    let checkForUpdatesButton: ClosureButton
    let replayOnboardingButton: ClosureButton

    init(
        header: NSView,
        theme: NotchTheme,
        localHealth: LocalHostHealth,
        hosts: [RemoteHost],
        health: RemoteHostHealthSnapshot,
        hostField: NSTextField,
        statusLabel: NSTextField,
        versionDescription: String,
        refreshConnections: @escaping () -> Void,
        pairHost: @escaping () -> Void,
        removeHost: @escaping (RemoteHost) -> Void,
        replayOnboarding: @escaping () -> Void,
        uninstall: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        let configuredHosts = hosts.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        let displayedHealth = RemoteHostHealthSnapshot(
            hosts: configuredHosts,
            healthByHostID: health.healthByHostID,
            isRefreshing: health.isRefreshing
        )
        self.displayedHealth = displayedHealth
        remoteSummaryLabel = SettingsViewFactory.label(
            "",
            size: 9.5,
            weight: .semibold,
            color: theme.tertiaryText,
            theme: theme
        )
        remoteRefreshButton = ClosureButton(handler: refreshConnections)

        let rows = configuredHosts.map { host in
            let row = RemoteConnectionRowView(host: host) { removeHost(host) }
            row.update(
                health: displayedHealth.health(for: host),
                refreshing: displayedHealth.isRefreshing
            )
            return (host.id, row)
        }
        remoteRows = Dictionary(uniqueKeysWithValues: rows)

        let check = ClosureButton(handler: checkForUpdates)
        checkForUpdatesButton = check
        let replay = ClosureButton(handler: replayOnboarding)
        replayOnboardingButton = replay
        super.init(frame: .zero)

        let title = SettingsViewFactory.label(
            "Connections",
            size: 25,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let subtitle = SettingsViewFactory.label(
            "Choose where completed Codex tasks can reach this Mac.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        replay.title = "Replay Onboarding…"
        replay.toolTip = "Run the guided Codex Notch setup again"
        SettingsViewFactory.style(replay, as: .secondary, theme: theme)
        let local = Self.connectionRow(
            label: "This Mac",
            detail: localHealth.isWorking ? "Local hook · Working" : "Local hook · Needs setup",
            theme: theme,
            working: localHealth.isWorking,
            trailingView: replay
        )
        local.toolTip = localHealth.statusLine
        let remoteTitle = SettingsViewFactory.label(
            "REMOTE UBUNTU HOSTS",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText,
            theme: theme
        )
        remoteSummaryLabel.alignment = .right
        remoteSummaryLabel.setContentCompressionResistancePriority(
            .defaultHigh,
            for: .horizontal
        )
        remoteRefreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Refresh remote host status"
        )
        remoteRefreshButton.contentTintColor = theme.secondaryText
        remoteRefreshButton.toolTip = "Check remote hosts now"
        remoteRefreshButton.translatesAutoresizingMaskIntoConstraints = false
        let remoteHeader = NSStackView(views: [
            remoteTitle,
            NSView(),
            remoteSummaryLabel,
            remoteRefreshButton,
        ])
        remoteHeader.orientation = .horizontal
        remoteHeader.alignment = .centerY
        remoteHeader.spacing = 8

        let hostRows = configuredHosts.compactMap { remoteRows[$0.id] }
        let hostViews: [NSView] = hostRows.isEmpty
            ? [Self.emptyHostsLabel(theme: theme)]
            : hostRows
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
        hostField.translatesAutoresizingMaskIntoConstraints = false
        let pair = ClosureButton(handler: pairHost)
        pair.title = "Pair"
        SettingsViewFactory.style(pair, as: .primary, theme: theme)
        let pairRow = NSStackView(views: [hostField, pair])
        pairRow.orientation = .horizontal
        pairRow.spacing = 10

        let uninstallButton = ClosureButton(handler: uninstall)
        uninstallButton.title = "Uninstall Codex Notch…"
        SettingsViewFactory.style(uninstallButton, as: .destructive, theme: theme)
        let version = SettingsViewFactory.label(
            versionDescription,
            size: 11,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.34),
            theme: theme
        )
        version.toolTip = "Installed Codex Notch version"
        check.title = "Check for Updates"
        check.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Check for Codex Notch updates"
        )
        check.imagePosition = .imageLeading
        check.imageHugsTitle = true
        check.toolTip = "Check for a newer version of Codex Notch"
        SettingsViewFactory.style(check, as: .secondary, theme: theme)
        let done = ClosureButton(handler: close)
        done.title = "Done"
        SettingsViewFactory.style(done, as: .secondary, theme: theme)
        let footer = NSStackView(views: [
            uninstallButton,
            NSView(),
            version,
            check,
            done,
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        statusLabel.stringValue = ""
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [
            header,
            title,
            subtitle,
            local,
            remoteHeader,
            hostScroll,
            pairRow,
            statusLabel,
            footer,
        ])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(28, after: local)
        stack.setCustomSpacing(8, after: remoteHeader)
        stack.setCustomSpacing(18, after: hostScroll)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            local.widthAnchor.constraint(equalTo: stack.widthAnchor),
            replay.widthAnchor.constraint(equalToConstant: 154),
            replay.heightAnchor.constraint(equalToConstant: 34),
            remoteHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            remoteRefreshButton.widthAnchor.constraint(equalToConstant: 26),
            remoteRefreshButton.heightAnchor.constraint(equalToConstant: 26),
            hostScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostScroll.heightAnchor.constraint(equalToConstant: min(listContentHeight, 182)),
            pairRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostField.heightAnchor.constraint(equalToConstant: 40),
            pair.widthAnchor.constraint(equalToConstant: 92),
            pair.heightAnchor.constraint(equalToConstant: 40),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            uninstallButton.widthAnchor.constraint(equalToConstant: 172),
            uninstallButton.heightAnchor.constraint(equalToConstant: 40),
            check.widthAnchor.constraint(equalToConstant: 148),
            check.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func connectionRow(
        label: String,
        detail: String,
        theme: NotchTheme,
        working: Bool,
        trailingView: NSView? = nil
    ) -> NSView {
        let indicator = NSImageView(image: NSImage(
            systemSymbolName: working ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        indicator.contentTintColor = working ? theme.accent : .systemOrange
        let name = SettingsViewFactory.label(
            label,
            size: 13,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let secondary = SettingsViewFactory.label(
            detail,
            size: 11,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let text = NSStackView(views: [name, secondary])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let rowViews = [indicator, text, NSView()] + (trailingView.map { [$0] } ?? [])
        let row = NSStackView(views: rowViews)
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

    private static func emptyHostsLabel(theme: NotchTheme) -> NSView {
        let label = SettingsViewFactory.label(
            "No remote hosts paired",
            size: 12,
            weight: .regular,
            color: theme.tertiaryText,
            theme: theme
        )
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}
