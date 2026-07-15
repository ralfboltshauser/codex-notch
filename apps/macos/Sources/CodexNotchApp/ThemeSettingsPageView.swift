import AppKit

final class ThemeSettingsPageView: NSView {
    private(set) var cards: [ThemeCardButton] = []
    private(set) var checkForUpdatesButton: ClosureButton?

    init(
        header: NSView,
        theme: NotchTheme,
        selectedThemeID: NotchTheme.ID,
        versionDescription: String,
        selectTheme: @escaping (NotchTheme.ID) -> Void,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        super.init(frame: .zero)

        let title = SettingsViewFactory.label(
            "Make it yours",
            size: 25,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let subtitle = SettingsViewFactory.label(
            "A theme changes the notch, its feedback, and this space together.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let sectionTitle = SettingsViewFactory.label(
            "THEMES",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText,
            theme: theme
        )
        let hint = SettingsViewFactory.label(
            "Hover to preview in the notch · Click to keep it",
            size: 11,
            weight: .medium,
            color: theme.secondaryText,
            theme: theme
        )
        let sectionHeader = NSStackView(views: [sectionTitle, NSView(), hint])
        sectionHeader.orientation = .horizontal
        sectionHeader.alignment = .centerY

        cards = NotchTheme.all.map { palette in
            let card = ThemeCardButton(theme: palette)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.setSelected(palette.id == selectedThemeID)
            card.onSelect = selectTheme
            return card
        }
        let rows = stride(from: 0, to: cards.count, by: 3).map { start in
            SettingsViewFactory.cardRow(
                Array(cards[start..<min(start + 3, cards.count)]),
                height: 93
            )
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 10
        grid.distribution = .fillEqually
        NSLayoutConstraint.activate(
            rows.map { $0.widthAnchor.constraint(equalTo: grid.widthAnchor) }
        )

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
            sectionHeader,
            grid,
            NSView(),
            footer.view,
        ])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(28, after: subtitle)
        stack.setCustomSpacing(9, after: sectionHeader)
        stack.setCustomSpacing(18, after: grid)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sectionHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.heightAnchor.constraint(
                equalToConstant: CGFloat(rows.count * 93 + max(rows.count - 1, 0) * 10)
            ),
            footer.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            footer.checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            footer.done.widthAnchor.constraint(equalToConstant: 96),
            footer.done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
