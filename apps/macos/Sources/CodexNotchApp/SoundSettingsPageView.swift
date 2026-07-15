import AppKit

final class SoundSettingsPageView: NSView {
    private(set) var cards: [NotificationSoundCardButton] = []
    private(set) var checkForUpdatesButton: ClosureButton?

    init(
        header: NSView,
        theme: NotchTheme,
        selectedSound: NotificationSound,
        versionDescription: String,
        selectSound: @escaping (NotificationSound) -> Void,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        super.init(frame: .zero)

        let title = SettingsViewFactory.label(
            "A finish worth hearing",
            size: 25,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let subtitle = SettingsViewFactory.label(
            "Six short completion tones, designed to stay satisfying even on a busy day.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        let sectionTitle = SettingsViewFactory.label(
            "COMPLETION TONE",
            size: 10,
            weight: .bold,
            color: theme.tertiaryText,
            theme: theme
        )
        let hint = SettingsViewFactory.label(
            "Click any sound to preview it",
            size: 11,
            weight: .medium,
            color: theme.secondaryText,
            theme: theme
        )
        let sectionHeader = NSStackView(views: [sectionTitle, NSView(), hint])
        sectionHeader.orientation = .horizontal
        sectionHeader.alignment = .centerY

        let audibleCards = NotificationSound.allCases
            .filter { $0 != .none }
            .map { sound in
                let card = NotificationSoundCardButton(sound: sound, theme: theme)
                card.translatesAutoresizingMaskIntoConstraints = false
                card.setSelected(sound == selectedSound)
                card.onSelect = selectSound
                return card
            }
        let rows = stride(from: 0, to: audibleCards.count, by: 3).map { start in
            SettingsViewFactory.cardRow(
                Array(audibleCards[start..<min(start + 3, audibleCards.count)]),
                height: 72
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

        let silent = NotificationSoundCardButton(sound: .none, theme: theme)
        silent.translatesAutoresizingMaskIntoConstraints = false
        silent.setSelected(selectedSound == .none)
        silent.onSelect = selectSound
        cards = audibleCards + [silent]

        let contextIcon = NSImageView(image: NSImage(
            systemSymbolName: "bell.badge.fill",
            accessibilityDescription: nil
        ) ?? NSImage())
        contextIcon.contentTintColor = theme.accent
        contextIcon.translatesAutoresizingMaskIntoConstraints = false
        let context = SettingsViewFactory.label(
            "Sounds play only for newly accepted local or remote Stop-hook events. Opening the notch yourself stays quiet.",
            size: 11.5,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
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
            silent,
            contextRow,
            footer.view,
        ])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(27, after: subtitle)
        stack.setCustomSpacing(9, after: sectionHeader)
        stack.setCustomSpacing(10, after: grid)
        stack.setCustomSpacing(18, after: silent)
        stack.setCustomSpacing(20, after: contextRow)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sectionHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.heightAnchor.constraint(
                equalToConstant: CGFloat(rows.count * 72 + max(rows.count - 1, 0) * 10)
            ),
            silent.widthAnchor.constraint(equalTo: stack.widthAnchor),
            silent.heightAnchor.constraint(equalToConstant: 58),
            contextRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            contextIcon.widthAnchor.constraint(equalToConstant: 18),
            contextIcon.heightAnchor.constraint(equalToConstant: 18),
            footer.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            footer.checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            footer.done.widthAnchor.constraint(equalToConstant: 96),
            footer.done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
