import AppKit
import CodexNotchCore

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

final class OnboardingWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    static let completionKey = "onboardingComplete.v2"

    private let pairings: PairingStore
    private let pairer: RemoteHostPairer
    private let root = NSVisualEffectView()
    private let content = NSView()
    private let hostField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var working = false

    var onConnectionsChanged: (() -> Void)?
    var onUninstall: ((@escaping (Result<Void, Error>) -> Void) -> Void)?

    init(pairings: PairingStore, pairer: RemoteHostPairer) {
        self.pairings = pairings
        self.pairer = pairer
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
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

        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        window.contentView = root
        showAppropriateStep()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
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

    private func showAppropriateStep() {
        if CodexHookInstaller().isInstalled {
            buildConnections()
        } else {
            buildLocalSetup()
        }
    }

    private func resetContent() {
        content.removeFromSuperview()
        content.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 46),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -46),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -36),
        ])
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
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(views: [icon, title, subtitle, install, statusLabel, uninstall])
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
            self?.buildConnections()
        }
        done.title = "Hook trusted"
        stylePrimaryButton(done)

        let buttons = NSStackView(views: [review, done])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(views: [icon, title, subtitle, buttons, statusLabel])
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
        let title = makeLabel("Connections", size: 25, weight: .semibold, color: .white)
        let local = connectionRow(label: "This Mac", detail: "Local hook", removable: nil)

        let remoteTitle = makeLabel(
            "REMOTE UBUNTU HOSTS",
            size: 10,
            weight: .bold,
            color: NSColor.white.withAlphaComponent(0.42)
        )
        let hosts = pairings.hosts.map { host in
            connectionRow(label: host.label, detail: host.sshAlias) { [weak self] in
                self?.remove(host)
            }
        }
        let hostList = NSStackView(views: hosts.isEmpty ? [emptyHostsLabel()] : hosts)
        hostList.orientation = .vertical
        hostList.spacing = 7
        hostList.alignment = .leading

        hostField.placeholderString = "SSH host alias"
        hostField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hostField.textColor = .white
        hostField.backgroundColor = NSColor.white.withAlphaComponent(0.065)
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
        let footer = NSStackView(views: [uninstall, spacer, done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        statusLabel.stringValue = ""
        configureStatusLabel()

        let stack = NSStackView(views: [title, local, remoteTitle, hostList, pairRow, statusLabel, footer])
        configureStack(stack)
        stack.setCustomSpacing(22, after: title)
        stack.setCustomSpacing(28, after: local)
        stack.setCustomSpacing(8, after: remoteTitle)
        stack.setCustomSpacing(18, after: hostList)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            local.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostList.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pairRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostField.heightAnchor.constraint(equalToConstant: 40),
            pair.widthAnchor.constraint(equalToConstant: 92),
            pair.heightAnchor.constraint(equalToConstant: 40),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            uninstall.widthAnchor.constraint(equalToConstant: 172),
            uninstall.heightAnchor.constraint(equalToConstant: 40),
            done.widthAnchor.constraint(equalToConstant: 96),
            done.heightAnchor.constraint(equalToConstant: 40),
        ])
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
                self.buildConnections()
                self.setStatus(error.localizedDescription, error: true)
            }
        }
    }

    private func installLocalHook() {
        do {
            try CodexHookInstaller().install()
            UserDefaults.standard.set(false, forKey: Self.completionKey)
            buildTrustStep()
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
                    self.buildConnections()
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
                    self.buildConnections()
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
        let indicator = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        indicator.contentTintColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        let name = makeLabel(label, size: 13, weight: .semibold, color: .white)
        let secondary = makeLabel(detail, size: 11, weight: .regular, color: NSColor.white.withAlphaComponent(0.4))
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
            remove.contentTintColor = NSColor.white.withAlphaComponent(0.45)
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
        row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        row.layer?.cornerRadius = 7
        row.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 52),
            indicator.widthAnchor.constraint(equalToConstant: 18),
            indicator.heightAnchor.constraint(equalToConstant: 18),
        ])
        return row
    }

    private func emptyHostsLabel() -> NSView {
        let label = makeLabel("No remote hosts paired", size: 12, weight: .regular, color: NSColor.white.withAlphaComponent(0.35))
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
        view.contentTintColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func stylePrimaryButton(_ button: ClosureButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .black
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1).cgColor
        button.layer?.cornerRadius = 7
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func styleSecondaryButton(_ button: ClosureButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.82)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        button.layer?.cornerRadius = 7
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
