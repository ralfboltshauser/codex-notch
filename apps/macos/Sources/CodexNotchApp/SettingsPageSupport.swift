import AppKit

enum SettingsButtonRole {
    case primary
    case secondary
    case destructive
}

struct StandardSettingsFooter {
    let view: NSStackView
    let checkForUpdates: ClosureButton
    let done: ClosureButton
}

enum SettingsViewFactory {
    static func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        theme: NotchTheme = ThemeStore.shared.activeTheme
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = theme.font(ofSize: size, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func configureVerticalStack(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
    }

    static func style(
        _ button: ClosureButton,
        as role: SettingsButtonRole,
        theme: NotchTheme = ThemeStore.shared.activeTheme
    ) {
        button.bezelStyle = .rounded
        button.wantsLayer = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer?.cornerCurve = .continuous
        switch role {
        case .primary:
            button.font = theme.font(ofSize: 13, weight: .semibold)
            button.contentTintColor = .black
            button.layer?.backgroundColor = theme.accent.cgColor
            button.layer?.cornerRadius = 9
        case .secondary:
            button.font = theme.font(ofSize: 12.5, weight: .semibold)
            button.contentTintColor = theme.primaryText
            button.layer?.backgroundColor = theme.quietSurface.cgColor
            button.layer?.cornerRadius = 9
        case .destructive:
            button.font = .systemFont(ofSize: 12.5, weight: .semibold)
            button.contentTintColor = NSColor.systemRed.withAlphaComponent(0.9)
            button.layer?.backgroundColor = NSColor.systemRed
                .withAlphaComponent(0.10).cgColor
            button.layer?.cornerRadius = 7
        }
    }

    static func standardFooter(
        versionDescription: String,
        theme: NotchTheme = ThemeStore.shared.activeTheme,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) -> StandardSettingsFooter {
        let version = label(
            versionDescription,
            size: 11,
            weight: .regular,
            color: NSColor.white.withAlphaComponent(0.34),
            theme: theme
        )
        version.toolTip = "Installed Codex Notch version"

        let check = ClosureButton(handler: checkForUpdates)
        check.title = "Check for Updates"
        check.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Check for Codex Notch updates"
        )
        check.imagePosition = .imageLeading
        check.imageHugsTitle = true
        check.toolTip = "Check for a newer version of Codex Notch"
        style(check, as: .secondary, theme: theme)

        let done = ClosureButton(handler: close)
        done.title = "Done"
        style(done, as: .secondary, theme: theme)

        let footer = NSStackView(views: [version, check, NSView(), done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        return StandardSettingsFooter(
            view: footer,
            checkForUpdates: check,
            done: done
        )
    }

    static func cardRow<Card: NSView>(
        _ cards: [Card],
        height: CGFloat
    ) -> NSStackView {
        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        NSLayoutConstraint.activate(cards.map {
            $0.heightAnchor.constraint(equalToConstant: height)
        })
        return row
    }

    static func install(_ page: NSView, in container: NSView) {
        page.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            page.topAnchor.constraint(equalTo: container.topAnchor),
            page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
