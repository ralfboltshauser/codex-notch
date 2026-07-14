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

final class NotchThemePreviewView: NSView {
    private let scene = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let island = CAGradientLayer()
    private let islandMask = CAShapeLayer()
    private let accentDot = CALayer()
    private let sampleRow = CALayer()
    private let badge = CALayer()
    private let taskLabel = NSTextField(labelWithString: "A task just finished")
    private let sourceLabel = NSTextField(labelWithString: "ralfs-ubuntu")
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        scene.startPoint = CGPoint(x: 0, y: 1)
        scene.endPoint = CGPoint(x: 1, y: 0)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        island.startPoint = CGPoint(x: 0.5, y: 0)
        island.endPoint = CGPoint(x: 0.5, y: 1)
        island.locations = [0, 0.70, 1]
        island.mask = islandMask
        layer?.addSublayer(scene)
        layer?.addSublayer(glow)
        layer?.addSublayer(island)
        island.addSublayer(accentDot)
        island.addSublayer(sampleRow)
        island.addSublayer(badge)

        taskLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        taskLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(taskLabel)
        addSubview(sourceLabel)
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
        guard let layer else { return }
        scene.frame = layer.bounds
        glow.frame = layer.bounds.insetBy(dx: -bounds.width * 0.15, dy: -bounds.height * 0.8)

        let islandWidth = min(bounds.width - 72, 520)
        let islandHeight: CGFloat = 104
        island.frame = CGRect(
            x: (bounds.width - islandWidth) / 2,
            y: 0,
            width: islandWidth,
            height: islandHeight
        )
        islandMask.frame = island.bounds
        islandMask.path = previewIslandPath(in: island.bounds)
        accentDot.frame = CGRect(x: 27, y: 65, width: 8, height: 8)
        accentDot.cornerRadius = 4
        sampleRow.frame = CGRect(x: 18, y: 15, width: islandWidth - 36, height: 38)
        sampleRow.cornerRadius = 11
        sampleRow.cornerCurve = .continuous
        badge.frame = CGRect(x: 28, y: 24, width: 20, height: 20)
        badge.cornerRadius = 10

        taskLabel.frame = CGRect(
            x: island.frame.minX + 60,
            y: island.frame.minY + 28,
            width: 220,
            height: 17
        )
        sourceLabel.frame = CGRect(
            x: island.frame.maxX - 122,
            y: island.frame.minY + 29,
            width: 94,
            height: 14
        )
    }

    private func previewIslandPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let body = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - 23)
        path.addRoundedRect(in: body, cornerWidth: 24, cornerHeight: 24)
        let neckWidth: CGFloat = 108
        let neck = CGRect(
            x: (rect.width - neckWidth) / 2,
            y: body.maxY - 8,
            width: neckWidth,
            height: 31
        )
        path.addRoundedRect(in: neck, cornerWidth: 11, cornerHeight: 11)
        return path
    }

    private func applyTheme(animated: Bool) {
        let theme = ThemeStore.shared.activeTheme
        let sceneColors = [
            theme.windowTint.blended(withFraction: 0.16, of: theme.secondaryAccent)?.cgColor
                ?? theme.windowTint.cgColor,
            NSColor.black.withAlphaComponent(0.84).cgColor,
        ]
        let glowColors = [
            theme.accent.withAlphaComponent(0.20).cgColor,
            theme.secondaryAccent.withAlphaComponent(0.05).cgColor,
            NSColor.clear.cgColor,
        ]
        let islandColors = [theme.hudBottom.cgColor, theme.hudTop.cgColor, NSColor.black.cgColor]

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateColors(layer: scene, to: sceneColors, key: "sceneTheme")
            animateColors(layer: glow, to: glowColors, key: "glowTheme")
            animateColors(layer: island, to: islandColors, key: "islandTheme")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.colors = sceneColors
        glow.colors = glowColors
        island.colors = islandColors
        layer?.borderColor = theme.border.cgColor
        accentDot.backgroundColor = theme.accent.cgColor
        sampleRow.backgroundColor = theme.hoverSurface.cgColor
        badge.backgroundColor = theme.accent.withAlphaComponent(0.18).cgColor
        taskLabel.textColor = theme.primaryText
        sourceLabel.textColor = theme.secondaryText
        CATransaction.commit()
    }

    private func animateColors(layer: CAGradientLayer, to colors: [CGColor], key: String) {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = layer.presentation()?.colors ?? layer.colors
        animation.toValue = colors
        animation.duration = 0.18
        animation.timingFunction = NotchMotion.ease
        layer.add(animation, forKey: key)
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

        nameLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        nameLabel.textColor = theme.primaryText
        moodLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
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
