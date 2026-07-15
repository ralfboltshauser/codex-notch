import AppKit

enum SettingsPage: CaseIterable {
    case appearance
    case tasks
    case sounds
    case connections
    case changelog

    var title: String {
        switch self {
        case .appearance: return "Themes"
        case .tasks: return "Tasks"
        case .sounds: return "Sounds"
        case .connections: return "Connections"
        case .changelog: return "Changelog"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .tasks: return "bolt.fill"
        case .sounds: return "waveform"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .changelog: return "clock.arrow.circlepath"
        }
    }
}

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

final class SettingsNavigationHeaderView: NSStackView {
    let buttons: [SettingsNavigationButton]

    init(
        selectedPage: SettingsPage,
        theme: NotchTheme,
        navigate: @escaping (SettingsPage) -> Void
    ) {
        let mark = NSImageView(image: NSImage(
            systemSymbolName: "sparkles.rectangle.stack.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        mark.contentTintColor = theme.accent
        mark.translatesAutoresizingMaskIntoConstraints = false
        let product = SettingsViewFactory.label(
            "Codex Notch",
            size: 14,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        buttons = SettingsPage.allCases.map { page in
            let active = page == selectedPage
            let button = SettingsNavigationButton { navigate(page) }
            button.title = page.title
            button.image = NSImage(
                systemSymbolName: page.symbol,
                accessibilityDescription: nil
            )
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = theme.font(
                ofSize: 11.5,
                weight: active ? .semibold : .medium
            )
            button.contentTintColor = active ? theme.primaryText : theme.secondaryText
            button.layer?.backgroundColor = (
                active ? theme.hoverSurface : NSColor.clear
            ).cgColor
            button.layer?.cornerRadius = 9
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
        let navigation = NSStackView(views: buttons)
        navigation.orientation = .horizontal
        navigation.spacing = 5
        navigation.alignment = .centerY

        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 9
        [mark, product, NSView(), navigation].forEach(addArrangedSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            mark.widthAnchor.constraint(equalToConstant: 19),
            mark.heightAnchor.constraint(equalToConstant: 19),
        ] + buttons.map { $0.heightAnchor.constraint(equalToConstant: 30) })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
            health.leadingAnchor.constraint(
                greaterThanOrEqualTo: identity.trailingAnchor,
                constant: 12
            ),
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

final class ChangelogReleaseCardView: NSView {
    let release: ChangelogRelease

    static func height(for release: ChangelogRelease) -> CGFloat {
        68 + CGFloat(release.changes.count * 40)
    }

    init(release: ChangelogRelease, currentVersion: String?) {
        self.release = release
        super.init(frame: .zero)
        let theme = ThemeStore.shared.activeTheme
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = theme.quietSurface.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        let version = label(
            "v\(release.version)",
            size: 11,
            weight: .bold,
            color: theme.accent
        )
        version.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        let date = label(
            Self.displayDate(release.date),
            size: 10.5,
            weight: .medium,
            color: theme.tertiaryText
        )
        date.alignment = .right
        var headerViews: [NSView] = [version]
        if release.version == currentVersion {
            let current = label("CURRENT", size: 9, weight: .bold, color: theme.accent)
            current.alignment = .center
            current.wantsLayer = true
            current.layer?.backgroundColor = theme.accent.withAlphaComponent(0.12).cgColor
            current.layer?.cornerRadius = 7
            current.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                current.widthAnchor.constraint(equalToConstant: 58),
                current.heightAnchor.constraint(equalToConstant: 18),
            ])
            headerViews.append(current)
        }
        headerViews.append(contentsOf: [NSView(), date])
        let header = NSStackView(views: headerViews)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let title = label(
            release.title,
            size: 14,
            weight: .semibold,
            color: theme.primaryText
        )
        title.lineBreakMode = .byTruncatingTail

        let bullets = release.changes.map { change -> NSView in
            let dot = NSView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.backgroundColor = theme.accent.withAlphaComponent(0.78).cgColor
            dot.layer?.cornerRadius = 2.5
            let text = label(
                change,
                size: 11.5,
                weight: .regular,
                color: theme.secondaryText
            )
            text.maximumNumberOfLines = 2
            text.lineBreakMode = .byWordWrapping
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [dot, text])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 32),
                dot.widthAnchor.constraint(equalToConstant: 5),
                dot.heightAnchor.constraint(equalToConstant: 5),
            ])
            return row
        }

        let stack = NSStackView(views: [header, title] + bullets)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height(for: release)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ] + bullets.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        setAccessibilityLabel(
            "Codex Notch \(release.version), \(release.title). "
                + release.changes.joined(separator: ". ")
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = ThemeStore.shared.activeTheme.font(ofSize: size, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static func displayDate(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              (1...12).contains(month)
        else { return value }
        let months = [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ]
        return "\(months[month - 1]) \(parts[2]), \(parts[0])"
    }
}
