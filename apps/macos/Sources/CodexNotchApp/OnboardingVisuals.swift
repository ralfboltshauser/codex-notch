import AppKit
import QuartzCore

final class OnboardingProgressView: NSStackView {
    private let segments: [NSView]

    init(stepCount: Int = OnboardingStep.allCases.count) {
        segments = (0..<stepCount).map { _ in NSView() }
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        distribution = .fillEqually
        segments.forEach {
            $0.wantsLayer = true
            $0.layer?.cornerRadius = 1.5
            addArrangedSubview($0)
        }
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 3).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(step: OnboardingStep, theme: NotchTheme) {
        for (index, segment) in segments.enumerated() {
            segment.layer?.backgroundColor = (
                index <= step.rawValue
                    ? theme.accent.withAlphaComponent(index == step.rawValue ? 0.95 : 0.42)
                    : NSColor.white.withAlphaComponent(0.10)
            ).cgColor
        }
    }
}

final class OnboardingNotchPreviewView: NSView {
    enum Mode {
        case waiting
        case success
    }

    private let gradient = CAGradientLayer()
    private let island = NSView()
    private let camera = NSView()
    private let dot = NSView()
    private let row = NSView()
    private let rowIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hostLabel = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private let reduceMotion: () -> Bool

    init(mode: Mode, reduceMotion: @escaping () -> Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)

        [island, camera, dot, row].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.wantsLayer = true
        }
        island.layer?.cornerRadius = 25
        island.layer?.cornerCurve = .continuous
        camera.layer?.cornerRadius = 11
        camera.layer?.cornerCurve = .continuous
        dot.layer?.cornerRadius = 4
        row.layer?.cornerRadius = 13
        row.layer?.cornerCurve = .continuous

        rowIcon.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.alignment = .center

        addSubview(island)
        island.addSubview(camera)
        island.addSubview(dot)
        island.addSubview(row)
        row.addSubview(rowIcon)
        row.addSubview(titleLabel)
        row.addSubview(hostLabel)
        addSubview(caption)

        NSLayoutConstraint.activate([
            island.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            island.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            island.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            island.heightAnchor.constraint(equalToConstant: 112),
            camera.centerXAnchor.constraint(equalTo: island.centerXAnchor),
            camera.topAnchor.constraint(equalTo: island.topAnchor, constant: -16),
            camera.widthAnchor.constraint(equalToConstant: 92),
            camera.heightAnchor.constraint(equalToConstant: 27),
            dot.leadingAnchor.constraint(equalTo: island.leadingAnchor, constant: 20),
            dot.topAnchor.constraint(equalTo: island.topAnchor, constant: 18),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: island.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: island.trailingAnchor, constant: -18),
            row.bottomAnchor.constraint(equalTo: island.bottomAnchor, constant: -17),
            row.heightAnchor.constraint(equalToConstant: 48),
            rowIcon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
            rowIcon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rowIcon.widthAnchor.constraint(equalToConstant: 20),
            rowIcon.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: rowIcon.trailingAnchor, constant: 11),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            hostLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            hostLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -15),
            hostLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -17),
        ])
        apply(mode: mode)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    func apply(mode: Mode) {
        let theme = ThemeStore.shared.activeTheme
        gradient.colors = [
            theme.accent.withAlphaComponent(0.19).cgColor,
            theme.hudBottom.withAlphaComponent(0.72).cgColor,
            NSColor.black.withAlphaComponent(0.88).cgColor,
        ]
        layer?.borderColor = theme.accent.withAlphaComponent(0.20).cgColor
        island.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.94).cgColor
        camera.layer?.backgroundColor = NSColor.black.cgColor
        dot.layer?.backgroundColor = theme.accent.cgColor
        row.layer?.backgroundColor = theme.accent.withAlphaComponent(0.14).cgColor
        rowIcon.image = NSImage(
            systemSymbolName: mode == .success ? "checkmark.circle.fill" : "sparkles",
            accessibilityDescription: nil
        )
        rowIcon.contentTintColor = theme.accent
        titleLabel.stringValue = mode == .success
            ? "Your first task is within reach"
            : "A Codex task just finished"
        titleLabel.font = theme.font(ofSize: 14, weight: .semibold)
        titleLabel.textColor = theme.primaryText
        hostLabel.stringValue = "This Mac"
        hostLabel.font = theme.font(ofSize: 11, weight: .semibold)
        hostLabel.textColor = theme.secondaryText
        caption.stringValue = mode == .success
            ? "The real notch is ready whenever Codex finishes."
            : "Completion appears at the top—without stealing focus."
        caption.font = theme.font(ofSize: 11.5, weight: .medium)
        caption.textColor = theme.secondaryText
        setAccessibilityLabel("Codex Notch preview. \(titleLabel.stringValue). \(caption.stringValue)")
    }

    func playSuccessAnimation() {
        guard !reduceMotion(), let layer = row.layer else { return }
        let animation = CASpringAnimation(keyPath: "transform.translation.y")
        animation.fromValue = -8
        animation.toValue = 0
        animation.mass = 1
        animation.stiffness = 260
        animation.damping = 30
        animation.initialVelocity = 0
        animation.duration = min(animation.settlingDuration, 0.42)
        layer.add(animation, forKey: "onboardingSuccess")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.20
        fade.timingFunction = NotchMotion.easeOut
        layer.add(fade, forKey: "onboardingSuccessFade")
    }
}

final class OnboardingStatusRow: NSView {
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String, detail: String, complete: Bool, theme: NotchTheme) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = theme.quietSurface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (complete
            ? theme.accent.withAlphaComponent(0.35)
            : theme.border).cgColor

        icon.image = NSImage(
            systemSymbolName: complete ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: complete ? "Complete" : "Incomplete"
        )
        icon.contentTintColor = complete ? theme.accent : theme.tertiaryText
        icon.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = theme.font(ofSize: 13, weight: .semibold)
        titleLabel.textColor = theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.stringValue = detail
        detailLabel.font = theme.font(ofSize: 10.5, weight: .regular)
        detailLabel.textColor = theme.secondaryText
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        [icon, titleLabel, detailLabel].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 57),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 19),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        setAccessibilityLabel("\(title). \(complete ? "Complete" : detail)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class OnboardingKeycapView: NSView {
    init(_ key: String, theme: NotchTheme) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        let label = SettingsViewFactory.label(
            key,
            size: 16,
            weight: .semibold,
            color: theme.primaryText,
            theme: theme
        )
        label.alignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            heightAnchor.constraint(equalToConstant: 38),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
