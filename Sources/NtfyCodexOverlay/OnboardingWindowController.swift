import AppKit

final class OnboardingWindowController: NSWindowController, NSTextFieldDelegate {
    static let completionKey = "onboardingComplete.v1"

    private let root = NSVisualEffectView()
    private let content = NSView()
    private let urlField = NSTextField()
    private let primaryButton = ClosureButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let configuredTopic: URL?
    private var installing = false

    var onConfigured: ((URL) -> Void)?

    init(configuredTopic: URL?) {
        self.configuredTopic = configuredTopic
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        super.init(window: window)

        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        window.contentView = root
        showAppropriateStep()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showAppropriateStep()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func showAppropriateStep() {
        let installer = CodexHookInstaller()
        let completed = UserDefaults.standard.bool(forKey: Self.completionKey)
        if configuredTopic != nil && installer.isInstalled && !completed {
            buildTrustStep()
        } else {
            buildConfigurationStep(isSettings: completed && configuredTopic != nil)
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
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -38),
        ])
    }

    private func buildConfigurationStep(isSettings: Bool) {
        resetContent()
        let icon = makeIcon(symbol: "bolt.horizontal.circle.fill")
        let title = makeLabel(
            isSettings ? "Connection settings" : "Finished tasks, without the interruption.",
            size: 25,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.96)
        )
        let subtitle = makeLabel(
            isSettings
                ? "Update the ntfy topic used by the Codex hook and this Mac."
                : "One ntfy URL connects Codex to a focus-safe shortcut overlay.",
            size: 14,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.52)
        )
        subtitle.maximumNumberOfLines = 2

        let fieldLabel = makeLabel(
            "NTFY TOPIC URL",
            size: 10,
            weight: .bold,
            color: NSColor.white.withAlphaComponent(0.42)
        )
        urlField.stringValue = configuredTopic?.absoluteString ?? ""
        urlField.placeholderString = "https://ntfy.example.com/my-codex-topic"
        urlField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        urlField.textColor = NSColor.white.withAlphaComponent(0.92)
        urlField.backgroundColor = NSColor.white.withAlphaComponent(0.065)
        urlField.isBezeled = true
        urlField.bezelStyle = .roundedBezel
        urlField.focusRingType = .none
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false

        let privacy = makeLabel(
            "The URL stays on this Mac. The hook sends the task title and Codex deep link—nothing else.",
            size: 11,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.34)
        )
        privacy.maximumNumberOfLines = 2

        primaryButton.title = isSettings ? "Save connection" : "Connect & install hook"
        stylePrimaryButton(primaryButton)
        primaryButton.handler = { [weak self] in self?.connectAndInstall() }

        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.textColor = NSColor.systemRed.withAlphaComponent(0.9)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, title, subtitle, fieldLabel, urlField, privacy, primaryButton, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(9, after: title)
        stack.setCustomSpacing(30, after: subtitle)
        stack.setCustomSpacing(7, after: fieldLabel)
        stack.setCustomSpacing(9, after: urlField)
        stack.setCustomSpacing(23, after: privacy)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            urlField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 42),
            primaryButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryButton.heightAnchor.constraint(equalToConstant: 42),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func buildTrustStep() {
        resetContent()
        let icon = makeIcon(symbol: "checkmark.seal.fill")
        let title = makeLabel(
            "Connected. One safety step remains.",
            size: 25,
            weight: .semibold,
            color: NSColor.white.withAlphaComponent(0.96)
        )
        let subtitle = makeLabel(
            "Codex requires you to review every new command hook before it can run.",
            size: 14,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.52)
        )
        subtitle.maximumNumberOfLines = 2

        let checks = NSStackView(views: [
            checkRow("ntfy topic connected", active: false),
            checkRow("Global Stop hook installed", active: false),
            checkRow("Trust “Sending completion to ntfy” in the Codex CLI", active: true),
        ])
        checks.orientation = .vertical
        checks.spacing = 9
        checks.alignment = .leading

        let guidance = makeLabel(
            "Open the Codex CLI, type /hooks, review the new user hook, and choose Trust. Codex records trust against the exact hook definition.",
            size: 12,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.43)
        )
        guidance.maximumNumberOfLines = 3

        let openCodex = ClosureButton { [weak self] in
            do {
                try CodexHookTrustLauncher.openCLI()
                self?.window?.orderFrontRegardless()
            } catch {
                self?.setStatus("Couldn’t open the Codex CLI: \(error.localizedDescription)", error: true)
            }
        }
        openCodex.title = "Open Codex CLI"
        styleSecondaryButton(openCodex)

        let done = ClosureButton { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completionKey)
            self?.close()
            NSApp.deactivate()
        }
        done.title = "I’ve trusted the hook"
        stylePrimaryButton(done)

        let buttons = NSStackView(views: [openCodex, done])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually

        statusLabel.stringValue = ""
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, title, subtitle, checks, guidance, buttons, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(9, after: title)
        stack.setCustomSpacing(26, after: subtitle)
        stack.setCustomSpacing(18, after: checks)
        stack.setCustomSpacing(25, after: guidance)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
            checks.widthAnchor.constraint(equalTo: stack.widthAnchor),
            guidance.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            openCodex.heightAnchor.constraint(equalToConstant: 42),
            done.heightAnchor.constraint(equalToConstant: 42),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func connectAndInstall() {
        guard !installing else { return }
        guard let topic = AppConfiguration.normalizedTopicURL(from: urlField.stringValue) else {
            setStatus("Enter an HTTPS ntfy topic URL. HTTP is accepted only for localhost.", error: true)
            return
        }
        let configuration = AppConfiguration(topicURL: topic)
        guard let testURL = configuration.subscriptionURL(parameters: ["poll": "1", "since": "latest"]) else {
            setStatus("That topic URL could not be read.", error: true)
            return
        }

        installing = true
        primaryButton.isEnabled = false
        primaryButton.title = "Connecting…"
        setStatus("Checking the ntfy topic…", error: false)
        var request = URLRequest(url: testURL, timeoutInterval: 10)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] _, response, networkError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.installing = false
                self.primaryButton.isEnabled = true
                self.primaryButton.title = "Connect & install hook"
                guard networkError == nil,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    self.setStatus("Couldn’t connect. Check the URL and topic access.", error: true)
                    return
                }
                do {
                    try configuration.save()
                    try CodexHookInstaller().install()
                    UserDefaults.standard.set(false, forKey: Self.completionKey)
                    self.onConfigured?(topic)
                    self.buildTrustStep()
                } catch {
                    self.setStatus("Couldn’t install the hook: \(error.localizedDescription)", error: true)
                }
            }
        }.resume()
    }

    private func setStatus(_ text: String, error: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = error
            ? NSColor.systemRed.withAlphaComponent(0.9)
            : NSColor.white.withAlphaComponent(0.4)
    }

    private func checkRow(_ text: String, active: Bool) -> NSView {
        let icon = NSImageView(image: NSImage(
            systemSymbolName: active ? "circle" : "checkmark.circle.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        icon.contentTintColor = active
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = makeLabel(
            text,
            size: 13,
            weight: active ? .semibold : .regular,
            color: NSColor.white.withAlphaComponent(active ? 0.86 : 0.58)
        )
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.spacing = 10
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
        ])
        return row
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
        button.layer?.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func styleSecondaryButton(_ button: ClosureButton) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.82)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        button.layer?.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
    }
}
