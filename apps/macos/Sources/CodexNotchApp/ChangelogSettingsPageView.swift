import AppKit

final class ChangelogSettingsPageView: NSView {
    private(set) var cards: [ChangelogReleaseCardView] = []
    private(set) var scrollView: NSScrollView?
    private(set) var checkForUpdatesButton: ClosureButton?

    init(
        header: NSView,
        theme: NotchTheme,
        releases: [ChangelogRelease],
        currentVersion: String?,
        versionDescription: String,
        checkForUpdates: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        super.init(frame: .zero)

        let title = SettingsViewFactory.label(
            "What’s new",
            size: 25,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        let subtitle = SettingsViewFactory.label(
            "A clear record of what changed in every recent Codex Notch release.",
            size: 13,
            weight: .regular,
            color: theme.secondaryText,
            theme: theme
        )
        cards = releases.map {
            ChangelogReleaseCardView(release: $0, currentVersion: currentVersion)
        }
        let list = FlippedHostStackView(arrangedViews: cards)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 10
        let contentHeight = cards.reduce(CGFloat(0)) {
            $0 + ChangelogReleaseCardView.height(for: $1.release)
        } + CGFloat(max(0, cards.count - 1) * 10)
        list.frame = NSRect(x: 0, y: 0, width: 636, height: contentHeight)
        list.autoresizingMask = [.width]
        cards.forEach {
            $0.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = contentHeight > 354
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .automatic
        scroll.documentView = list
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scrollView = scroll

        let footer = SettingsViewFactory.standardFooter(
            versionDescription: versionDescription,
            theme: theme,
            checkForUpdates: checkForUpdates,
            close: close
        )
        checkForUpdatesButton = footer.checkForUpdates
        let stack = NSStackView(views: [header, title, subtitle, scroll, footer.view])
        SettingsViewFactory.configureVerticalStack(stack)
        stack.spacing = 0
        stack.setCustomSpacing(28, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(22, after: subtitle)
        stack.setCustomSpacing(20, after: scroll)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 354),
            footer.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.checkForUpdates.widthAnchor.constraint(equalToConstant: 148),
            footer.checkForUpdates.heightAnchor.constraint(equalToConstant: 40),
            footer.done.widthAnchor.constraint(equalToConstant: 96),
            footer.done.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
