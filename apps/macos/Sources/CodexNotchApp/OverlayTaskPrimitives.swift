import AppKit

final class NumberBadgeView: NSView {
    private let numberText: String
    private let shortcutText: String?
    private let label: NSTextField

    init(number: Int, shortcut: String?, theme: NotchTheme) {
        numberText = "\(number)"
        shortcutText = shortcut
        label = NSTextField(labelWithString: numberText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.accent.withAlphaComponent(0.14).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = theme.primaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showShortcut(_ visible: Bool) {
        label.stringValue = visible ? (shortcutText ?? numberText) : numberText
    }

    var textForTesting: String { label.stringValue }
}

final class EmptyStateView: NSView {
    init(updateVersion: String?, theme: NotchTheme) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let iconWell = NSView()
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.wantsLayer = true
        iconWell.layer?.backgroundColor = theme.surface.cgColor
        iconWell.layer?.borderColor = theme.border.cgColor
        iconWell.layer?.borderWidth = 1
        iconWell.layer?.cornerRadius = 18
        iconWell.layer?.cornerCurve = .continuous

        let symbolName = updateVersion == nil ? "checkmark" : "arrow.down"
        let symbolDescription = updateVersion == nil ? "No completed tasks" : "Update ready"
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: symbolDescription
        ) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(icon)

        let title = NSTextField(labelWithString: updateVersion == nil ? "All clear" : "Update ready")
        title.font = theme.font(ofSize: 13, weight: .medium)
        title.textColor = theme.primaryText
        title.alignment = .center

        let detailText = updateVersion.map { "Codex Notch \($0) is ready to install." }
            ?? "Completed Codex tasks will appear here."
        let detail = NSTextField(labelWithString: detailText)
        detail.font = theme.font(ofSize: 11.5, weight: .regular)
        detail.textColor = theme.secondaryText
        detail.alignment = .center

        let settingsHint = NSTextField(labelWithString: "⌘,  Settings")
        settingsHint.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        settingsHint.textColor = theme.tertiaryText
        settingsHint.alignment = .center

        let stack = NSStackView(views: [iconWell, title, detail, settingsHint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(8, after: iconWell)
        stack.setCustomSpacing(9, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 104),
            iconWell.widthAnchor.constraint(equalToConstant: 36),
            iconWell.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
