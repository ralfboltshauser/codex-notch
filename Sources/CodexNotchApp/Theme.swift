import AppKit

struct NotchTheme: Equatable {
    enum Typography: String, CaseIterable {
        case system
        case rounded
        case serif
        case monospaced
    }

    enum ID: String, CaseIterable {
        case obsidian
        case aurora
        case ember
        case amethyst
        case cobalt
        case dune
        case blackout
        case letterpress
        case terminal
    }

    let id: ID
    let name: String
    let mood: String
    let accent: NSColor
    let secondaryAccent: NSColor
    let hudTop: NSColor
    let hudBottom: NSColor
    let windowTint: NSColor
    let typography: Typography

    var primaryText: NSColor { NSColor.white.withAlphaComponent(0.95) }
    var secondaryText: NSColor { NSColor.white.withAlphaComponent(0.58) }
    var tertiaryText: NSColor { NSColor.white.withAlphaComponent(0.38) }
    var quietSurface: NSColor { NSColor.white.withAlphaComponent(0.06) }
    var surface: NSColor { accent.withAlphaComponent(0.10) }
    var hoverSurface: NSColor { accent.withAlphaComponent(0.16) }
    var pressedSurface: NSColor { accent.withAlphaComponent(0.23) }
    var border: NSColor { NSColor.white.withAlphaComponent(0.10) }

    func font(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch typography {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded, .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let design: NSFontDescriptor.SystemDesign = typography == .rounded
                ? .rounded
                : .serif
            guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
    }

    static func == (lhs: NotchTheme, rhs: NotchTheme) -> Bool { lhs.id == rhs.id }

    static let all: [NotchTheme] = [
        NotchTheme(
            id: .obsidian,
            name: "Obsidian",
            mood: "Quiet · focused",
            accent: NSColor(hex: 0x68E8B7),
            secondaryAccent: NSColor(hex: 0xA6FFD7),
            hudTop: NSColor(hex: 0x020504),
            hudBottom: NSColor(hex: 0x07130F),
            windowTint: NSColor(hex: 0x07110E),
            typography: .system
        ),
        NotchTheme(
            id: .aurora,
            name: "Aurora",
            mood: "Luminous · calm",
            accent: NSColor(hex: 0x78E7FF),
            secondaryAccent: NSColor(hex: 0x948BFF),
            hudTop: NSColor(hex: 0x03060D),
            hudBottom: NSColor(hex: 0x09152A),
            windowTint: NSColor(hex: 0x091427),
            typography: .system
        ),
        NotchTheme(
            id: .ember,
            name: "Ember",
            mood: "Warm · energetic",
            accent: NSColor(hex: 0xFFAA70),
            secondaryAccent: NSColor(hex: 0xFF7189),
            hudTop: NSColor(hex: 0x090403),
            hudBottom: NSColor(hex: 0x24100B),
            windowTint: NSColor(hex: 0x21100D),
            typography: .system
        ),
        NotchTheme(
            id: .amethyst,
            name: "Amethyst",
            mood: "Dreamy · precise",
            accent: NSColor(hex: 0xCAA7FF),
            secondaryAccent: NSColor(hex: 0xF284C9),
            hudTop: NSColor(hex: 0x07040B),
            hudBottom: NSColor(hex: 0x1D0E28),
            windowTint: NSColor(hex: 0x1A1024),
            typography: .system
        ),
        NotchTheme(
            id: .cobalt,
            name: "Cobalt",
            mood: "Crisp · electric",
            accent: NSColor(hex: 0x70A7FF),
            secondaryAccent: NSColor(hex: 0x68F0DC),
            hudTop: NSColor(hex: 0x02050B),
            hudBottom: NSColor(hex: 0x08162B),
            windowTint: NSColor(hex: 0x0A172A),
            typography: .system
        ),
        NotchTheme(
            id: .dune,
            name: "Dune",
            mood: "Soft · considered",
            accent: NSColor(hex: 0xE7CA8B),
            secondaryAccent: NSColor(hex: 0xF5A96E),
            hudTop: NSColor(hex: 0x070604),
            hudBottom: NSColor(hex: 0x1B160D),
            windowTint: NSColor(hex: 0x19150F),
            typography: .system
        ),
        NotchTheme(
            id: .blackout,
            name: "Blackout",
            mood: "Pure black · zero glow",
            accent: NSColor.white,
            secondaryAccent: NSColor(hex: 0x77777F),
            hudTop: .black,
            hudBottom: .black,
            windowTint: .black,
            typography: .rounded
        ),
        NotchTheme(
            id: .letterpress,
            name: "Letterpress",
            mood: "Serif · editorial",
            accent: NSColor(hex: 0xF1D39A),
            secondaryAccent: NSColor(hex: 0xC7785D),
            hudTop: NSColor(hex: 0x080604),
            hudBottom: NSColor(hex: 0x241A12),
            windowTint: NSColor(hex: 0x1A130E),
            typography: .serif
        ),
        NotchTheme(
            id: .terminal,
            name: "Terminal",
            mood: "Mono · phosphor",
            accent: NSColor(hex: 0x77F6A6),
            secondaryAccent: NSColor(hex: 0xE4C65B),
            hudTop: NSColor(hex: 0x000302),
            hudBottom: NSColor(hex: 0x06150D),
            windowTint: NSColor(hex: 0x041009),
            typography: .monospaced
        ),
    ]

    static func theme(for id: ID) -> NotchTheme {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

final class ThemeStore {
    static let shared = ThemeStore()
    static let didChangeNotification = Notification.Name("CodexNotchThemeDidChange")
    static let defaultsKey = "appearance.theme.v1"

    private let defaults: UserDefaults
    private(set) var selectedID: NotchTheme.ID
    private(set) var previewID: NotchTheme.ID?

    var selectedTheme: NotchTheme { NotchTheme.theme(for: selectedID) }
    var activeTheme: NotchTheme { NotchTheme.theme(for: previewID ?? selectedID) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedID = defaults.string(forKey: Self.defaultsKey)
            .flatMap(NotchTheme.ID.init(rawValue:)) ?? .obsidian
    }

    func preview(_ id: NotchTheme.ID) {
        guard previewID != id else { return }
        previewID = id
        notify()
    }

    func endPreview(_ id: NotchTheme.ID? = nil) {
        if let id, previewID != id { return }
        guard previewID != nil else { return }
        previewID = nil
        notify()
    }

    func select(_ id: NotchTheme.ID) {
        let changed = selectedID != id || previewID != nil
        selectedID = id
        previewID = nil
        defaults.set(id.rawValue, forKey: Self.defaultsKey)
        if changed { notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
