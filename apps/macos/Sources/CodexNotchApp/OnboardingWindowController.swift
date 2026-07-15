import AppKit
import CodexNotchCore
import QuartzCore

final class OnboardingWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    static let completionKey = "onboardingComplete.v2"
    static let settingsContentSize = NSSize(width: 720, height: 650)

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
    private var selectedPage: SettingsPage = .connections
    private var themePreviewIsActive = false
    private var themeCards: [ThemeCardButton] = []
    private var soundCards: [NotificationSoundCardButton] = []
    private var settingsTabs: [SettingsNavigationButton] = []
    private var taskLayoutViews: [String: NSView] = [:]
    private var changelogCards: [ChangelogReleaseCardView] = []
    private weak var changelogScrollView: NSScrollView?

    var onConnectionsChanged: (() -> Void)?
    var onRefreshConnections: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onUninstall: ((@escaping (Result<Void, Error>) -> Void) -> Void)?
    var onThemePreviewVisibilityChanged: ((Bool, NSScreen?) -> Void)?

    var checkForUpdatesButtonForTesting: NSButton? { checkForUpdatesButton }
    var doNotDisturbButtonForTesting: NSButton? { doNotDisturbButton }
    var settingsTabTitlesForTesting: [String] { settingsTabs.map(\.title) }
    var selectedSettingsTabTitleForTesting: String { selectedPage.title }
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
    var settingsTabFramesForTesting: [NSRect] {
        root.layoutSubtreeIfNeeded()
        return settingsTabs.map { $0.convert($0.bounds, to: root) }
    }
    var settingsTabsHaveAmbiguityForTesting: Bool {
        root.layoutSubtreeIfNeeded()
        return settingsTabs.contains(where: \.hasAmbiguousLayout)
    }
    var renderedChangelogVersionsForTesting: [String] {
        changelogCards.map(\.release.version)
    }
    var changelogUsesVerticalScrollingForTesting: Bool {
        changelogScrollView?.hasVerticalScroller == true
    }
    var taskLayoutFramesForTesting: [String: NSRect] {
        root.layoutSubtreeIfNeeded()
        return taskLayoutViews.mapValues { $0.convert($0.bounds, to: root) }
    }
    var taskLayoutHasAmbiguityForTesting: Bool {
        root.layoutSubtreeIfNeeded()
        return taskLayoutViews.values.contains(where: \.hasAmbiguousLayout)
    }
    func showSoundsForTesting() {
        buildSettingsPage(.sounds)
    }

    func showThemesForTesting() {
        buildSettingsPage(.appearance)
    }

    func showTasksForTesting() {
        buildSettingsPage(.tasks)
    }

    func showChangelogForTesting() {
        buildSettingsPage(.changelog)
    }

    func selectSettingsTabForTesting(titled title: String) {
        settingsTabs.first(where: { $0.title == title })?.performClick(nil)
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
            contentRect: NSRect(origin: .zero, size: Self.settingsContentSize),
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
        window.contentMinSize = Self.settingsContentSize
        window.contentMaxSize = Self.settingsContentSize
        window.setContentSize(Self.settingsContentSize)
        window.center()
        super.init(window: window)
        window.delegate = self

        window.contentView = root
        installContentContainer()
        showAppropriateStep()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        setThemePreviewActive(false)
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
        updateThemePreviewVisibility()
    }

    func presentConnections() {
        selectedPage = .connections
        present()
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

    private func updateThemePreviewVisibility() {
        setThemePreviewActive(
            window?.isVisible == true && isHookInstalled() && selectedPage == .appearance
        )
    }

    private func setThemePreviewActive(_ active: Bool) {
        guard themePreviewIsActive != active else { return }
        themePreviewIsActive = active
        onThemePreviewVisibilityChanged?(active, window?.screen)
    }

    private func installContentContainer() {
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        root.addSubview(content)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.settingsContentSize.width),
            root.heightAnchor.constraint(equalToConstant: Self.settingsContentSize.height),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 42),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -42),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -32),
        ])
    }

    private func resetContent() {
        taskLayoutViews.removeAll()
        changelogCards.removeAll()
        changelogScrollView = nil
        content.subviews.forEach { $0.removeFromSuperview() }
        content.layer?.removeAllAnimations()
        content.layer?.opacity = 1
        content.layer?.transform = CATransform3DIdentity
    }

    private func buildSettingsPage(_ page: SettingsPage) {
        selectedPage = page
        ThemeStore.shared.endPreview()
        updateThemePreviewVisibility()
        switch page {
        case .appearance: buildAppearance()
        case .tasks: buildTasks()
        case .sounds: buildSounds()
        case .connections: buildConnections()
        case .changelog: buildChangelog()
        }
    }

    private func buildTasks() {
        resetContent()
        let page = TaskSettingsPageView(
            header: settingsHeader(selected: .tasks),
            theme: ThemeStore.shared.activeTheme,
            showsActiveTasks: ActiveTaskPreferences.shared.isVisible,
            doNotDisturbEnabled: doNotDisturbPreferences.isEnabled,
            versionDescription: Self.versionDescription(),
            toggleActiveTasks: { [weak self] in
                _ = ActiveTaskPreferences.shared.toggle()
                self?.buildTasks()
            },
            toggleDoNotDisturb: { [weak self] in
                guard let self else { return }
                _ = self.doNotDisturbPreferences.toggle()
                self.buildTasks()
            },
            checkForUpdates: { [weak self] in self?.onCheckForUpdates?() },
            close: { [weak self] in self?.close() }
        )
        SettingsViewFactory.install(page, in: content)
        taskLayoutViews = page.layoutViews
        doNotDisturbButton = page.doNotDisturbButton
        checkForUpdatesButton = page.checkForUpdatesButton
    }
    private func buildAppearance() {
        resetContent()
        let page = ThemeSettingsPageView(
            header: settingsHeader(selected: .appearance),
            theme: ThemeStore.shared.activeTheme,
            selectedThemeID: ThemeStore.shared.selectedID,
            versionDescription: Self.versionDescription(),
            selectTheme: { [weak self] id in
                ThemeStore.shared.select(id)
                self?.buildAppearance()
            },
            checkForUpdates: { [weak self] in self?.onCheckForUpdates?() },
            close: { [weak self] in self?.close() }
        )
        SettingsViewFactory.install(page, in: content)
        themeCards = page.cards
        checkForUpdatesButton = page.checkForUpdatesButton
    }
    private func buildSounds() {
        resetContent()
        let page = SoundSettingsPageView(
            header: settingsHeader(selected: .sounds),
            theme: ThemeStore.shared.activeTheme,
            selectedSound: notificationSounds.selectedSound,
            versionDescription: Self.versionDescription(),
            selectSound: { [weak self] sound in
                self?.notificationSounds.selectAndPreview(sound)
                self?.buildSounds()
            },
            checkForUpdates: { [weak self] in self?.onCheckForUpdates?() },
            close: { [weak self] in self?.close() }
        )
        SettingsViewFactory.install(page, in: content)
        soundCards = page.cards
        checkForUpdatesButton = page.checkForUpdatesButton
    }
    private func buildChangelog() {
        resetContent()
        let page = ChangelogSettingsPageView(
            header: settingsHeader(selected: .changelog),
            theme: ThemeStore.shared.activeTheme,
            releases: ChangelogCatalog.releases,
            currentVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            versionDescription: Self.versionDescription(),
            checkForUpdates: { [weak self] in self?.onCheckForUpdates?() },
            close: { [weak self] in self?.close() }
        )
        SettingsViewFactory.install(page, in: content)
        changelogCards = page.cards
        changelogScrollView = page.scrollView
        checkForUpdatesButton = page.checkForUpdatesButton
    }
    private func settingsHeader(selected: SettingsPage) -> NSView {
        let header = SettingsNavigationHeaderView(
            selectedPage: selected,
            theme: ThemeStore.shared.activeTheme
        ) { [weak self] page in
            self?.transitionContent { [weak self] in
                self?.buildSettingsPage(page)
            }
        }
        settingsTabs = header.buttons
        return header
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
        hostField.delegate = self
        let page = ConnectionSettingsPageView(
            header: settingsHeader(selected: .connections),
            theme: ThemeStore.shared.activeTheme,
            hosts: pairings.hosts,
            health: remoteHealth,
            hostField: hostField,
            statusLabel: statusLabel,
            versionDescription: Self.versionDescription(),
            refreshConnections: { [weak self] in self?.onRefreshConnections?() },
            pairHost: { [weak self] in self?.pairRemoteHost() },
            removeHost: { [weak self] host in self?.remove(host) },
            uninstall: { [weak self] in self?.confirmUninstall() },
            checkForUpdates: { [weak self] in self?.onCheckForUpdates?() },
            close: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.completionKey)
                self?.close()
            }
        )
        SettingsViewFactory.install(page, in: content)
        remoteHealth = page.displayedHealth
        remoteRows = page.remoteRows
        remoteSummaryLabel = page.remoteSummaryLabel
        remoteRefreshButton = page.remoteRefreshButton
        checkForUpdatesButton = page.checkForUpdatesButton
        updateRemoteHealth(page.displayedHealth)
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
        SettingsViewFactory.configureVerticalStack(stack)
    }

    private func makeIcon(symbol: String) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        view.contentTintColor = ThemeStore.shared.activeTheme.accent
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        SettingsViewFactory.label(
            text,
            size: size,
            weight: weight,
            color: color
        )
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

    private func stylePrimaryButton(_ button: ClosureButton) {
        SettingsViewFactory.style(button, as: .primary)
    }

    private func styleSecondaryButton(_ button: ClosureButton) {
        SettingsViewFactory.style(button, as: .secondary)
    }

    private func styleDestructiveButton(_ button: ClosureButton) {
        SettingsViewFactory.style(button, as: .destructive)
    }

    private func makeUninstallButton() -> ClosureButton {
        let button = ClosureButton { [weak self] in self?.confirmUninstall() }
        button.title = "Uninstall Codex Notch…"
        styleDestructiveButton(button)
        return button
    }
}
