import AppKit
import QuartzCore

final class ThemeBackdropView: NSVisualEffectView {
    private let tintLayer = CAGradientLayer()
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        tintLayer.startPoint = CGPoint(x: 0.1, y: 1)
        tintLayer.endPoint = CGPoint(x: 0.9, y: 0)
        layer?.addSublayer(tintLayer)
        applyTheme(animated: false)
        observer = NotificationCenter.default.addObserver(
            forName: ThemeStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.applyTheme(animated: true) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
    }

    private func applyTheme(animated: Bool) {
        let theme = ThemeStore.shared.activeTheme
        let colors = [
            theme.windowTint.withAlphaComponent(0.93).cgColor,
            theme.hudBottom.withAlphaComponent(0.82).cgColor,
            NSColor.black.withAlphaComponent(0.72).cgColor,
        ]
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CABasicAnimation(keyPath: "colors")
            transition.fromValue = tintLayer.presentation()?.colors ?? tintLayer.colors
            transition.toValue = colors
            transition.duration = 0.18
            transition.timingFunction = NotchMotion.ease
            tintLayer.add(transition, forKey: "themeTint")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.colors = colors
        CATransaction.commit()
    }
}

final class ThemeCardButton: NSButton {
    let theme: NotchTheme
    var onSelect: ((NotchTheme.ID) -> Void)?

    private let swatch = CAGradientLayer()
    private let nameLabel: NSTextField
    private let moodLabel: NSTextField
    private let selectedIcon: NSImageView
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var selectedTheme = false

    init(theme: NotchTheme) {
        self.theme = theme
        nameLabel = NSTextField(labelWithString: theme.name)
        moodLabel = NSTextField(labelWithString: theme.mood)
        selectedIcon = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Selected"
        ) ?? NSImage())
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        swatch.startPoint = CGPoint(x: 0, y: 0.5)
        swatch.endPoint = CGPoint(x: 1, y: 0.5)
        swatch.cornerRadius = 5
        layer?.addSublayer(swatch)

        nameLabel.font = theme.font(ofSize: 12.5, weight: .semibold)
        nameLabel.textColor = theme.primaryText
        moodLabel.font = theme.font(ofSize: 10.5, weight: .regular)
        moodLabel.textColor = theme.secondaryText
        selectedIcon.contentTintColor = theme.accent
        [nameLabel, moodLabel, selectedIcon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -27),
            moodLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            moodLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            selectedIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            selectedIcon.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            selectedIcon.widthAnchor.constraint(equalToConstant: 15),
            selectedIcon.heightAnchor.constraint(equalToConstant: 15),
        ])
        target = self
        action = #selector(chooseTheme)
        toolTip = "Preview \(theme.name); click to keep it"
        setAccessibilityLabel("\(theme.name) theme")
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        swatch.frame = CGRect(x: 12, y: bounds.height - 32, width: bounds.width - 24, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        ThemeStore.shared.preview(theme.id)
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        ThemeStore.shared.endPreview(theme.id)
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        selectedTheme = selected
        selectedIcon.isHidden = !selected
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        updateAppearance()
    }

    @objc private func chooseTheme() { onSelect?(theme.id) }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(NotchMotion.ease)
        swatch.colors = [
            theme.hudBottom.cgColor,
            theme.accent.cgColor,
            theme.secondaryAccent.cgColor,
        ]
        layer?.backgroundColor = (hovering ? theme.hoverSurface : theme.quietSurface).cgColor
        layer?.borderColor = selectedTheme
            ? theme.accent.withAlphaComponent(0.78).cgColor
            : (hovering ? theme.accent.withAlphaComponent(0.42) : theme.border).cgColor
        CATransaction.commit()
    }
}
