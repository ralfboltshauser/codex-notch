import AppKit
import Foundation
import QuartzCore

enum NotificationSound: String, CaseIterable, Equatable {
    case glassDrop = "glass-drop"
    case softPulse = "soft-pulse"
    case aurora
    case pebble
    case halo
    case prism
    case none

    static let preferenceKey = "completionSound.v1"
    static let defaultSound: NotificationSound = .glassDrop

    var name: String {
        switch self {
        case .glassDrop: return "Glass Drop"
        case .softPulse: return "Soft Pulse"
        case .aurora: return "Aurora"
        case .pebble: return "Pebble"
        case .halo: return "Halo"
        case .prism: return "Prism"
        case .none: return "No Sound"
        }
    }

    var detail: String {
        switch self {
        case .glassDrop: return "Crisp, luminous, and precise"
        case .softPulse: return "Warm, rounded, and understated"
        case .aurora: return "Airy with an upward shimmer"
        case .pebble: return "Tiny, tactile, and organic"
        case .halo: return "A calm two-note resolve"
        case .prism: return "Liquid, bright, and futuristic"
        case .none: return "Keep completion notifications silent"
        }
    }

    var resourceURL: URL? {
        guard self != .none else { return nil }
        return Bundle.module.url(
            forResource: rawValue,
            withExtension: "mp3",
            subdirectory: "Sounds"
        )
    }

    static func selected(in defaults: UserDefaults = .standard) -> NotificationSound {
        guard let stored = defaults.string(forKey: preferenceKey) else { return defaultSound }
        return NotificationSound(rawValue: stored) ?? defaultSound
    }

    func select(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

final class NotificationSoundPlayer: NSObject, NSSoundDelegate {
    private let defaults: UserDefaults
    private var activeSound: NSSound?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSound: NotificationSound {
        NotificationSound.selected(in: defaults)
    }

    func playSelected() {
        play(selectedSound)
    }

    func selectAndPreview(_ sound: NotificationSound) {
        sound.select(in: defaults)
        play(sound)
    }

    func play(_ sound: NotificationSound) {
        activeSound?.stop()
        activeSound = nil
        guard let url = sound.resourceURL,
              let playback = NSSound(contentsOf: url, byReference: true) else { return }
        playback.delegate = self
        activeSound = playback
        playback.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if activeSound === sound { activeSound = nil }
    }
}

final class NotificationSoundCardButton: NSButton {
    let notificationSound: NotificationSound
    var onSelect: ((NotificationSound) -> Void)?

    private let icon: NSImageView
    private let nameLabel: NSTextField
    private let detailLabel: NSTextField
    private let selectedIcon: NSImageView
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var selectedSound = false

    init(sound: NotificationSound) {
        notificationSound = sound
        icon = NSImageView(image: NSImage(
            systemSymbolName: sound == .none ? "speaker.slash.fill" : "waveform",
            accessibilityDescription: nil
        ) ?? NSImage())
        nameLabel = NSTextField(labelWithString: sound.name)
        detailLabel = NSTextField(labelWithString: sound.detail)
        selectedIcon = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Selected"
        ) ?? NSImage())
        super.init(frame: .zero)

        title = ""
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        let accent = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        icon.contentTintColor = accent
        nameLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        detailLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.48)
        detailLabel.lineBreakMode = .byTruncatingTail
        selectedIcon.contentTintColor = accent

        [icon, nameLabel, detailLabel, selectedIcon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: selectedIcon.leadingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            selectedIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            selectedIcon.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            selectedIcon.widthAnchor.constraint(equalToConstant: 15),
            selectedIcon.heightAnchor.constraint(equalToConstant: 15),
        ])

        target = self
        action = #selector(chooseSound)
        toolTip = sound == .none ? sound.detail : "Select and preview \(sound.name)"
        setAccessibilityLabel("\(sound.name) completion sound")
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateAppearance()
    }

    func setSelected(_ selected: Bool) {
        selectedSound = selected
        selectedIcon.isHidden = !selected
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        updateAppearance()
    }

    @objc private func chooseSound() { onSelect?(notificationSound) }

    private func updateAppearance() {
        let accent = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(NotchMotion.ease)
        layer?.backgroundColor = (
            selectedSound
                ? accent.withAlphaComponent(0.12)
                : NSColor.white.withAlphaComponent(hovering ? 0.09 : 0.055)
        ).cgColor
        layer?.borderColor = (
            selectedSound
                ? accent.withAlphaComponent(0.74)
                : NSColor.white.withAlphaComponent(hovering ? 0.18 : 0.08)
        ).cgColor
        CATransaction.commit()
    }
}
