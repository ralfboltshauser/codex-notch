import Foundation

enum AttentionMode: String, CaseIterable, Equatable {
    case notify
    case glance
    case quiet

    var title: String {
        switch self {
        case .notify: return "Notify"
        case .glance: return "Glance"
        case .quiet: return "Quiet"
        }
    }

    var systemImageName: String {
        switch self {
        case .notify: return "bell.fill"
        case .glance: return "eye.fill"
        case .quiet: return "moon.fill"
        }
    }

    var headerTitle: String { self == .quiet ? "Quiet" : "Codex" }
    var headerSystemImageName: String {
        self == .quiet ? "moon.fill" : "checkmark.circle.fill"
    }
    var headerAccessibilityDescription: String {
        self == .quiet ? "Codex Notch is collecting quietly" : "Codex tasks ready"
    }
    var helpText: String {
        switch self {
        case .notify: return "Open completions and play the selected sound"
        case .glance: return "Badge completions; still open tasks that need you"
        case .quiet: return "Collect without opening the notch or playing sound"
        }
    }
}

final class AttentionPreferences {
    static let shared = AttentionPreferences()
    static let modeKey = "attentionMode.v2"
    static let legacyDoNotDisturbKey = "doNotDisturbEnabled.v1"
    static let didChangeNotification = Notification.Name("AttentionPreferencesDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.modeKey) == nil,
           defaults.bool(forKey: Self.legacyDoNotDisturbKey) {
            defaults.set(AttentionMode.quiet.rawValue, forKey: Self.modeKey)
        }
    }

    var mode: AttentionMode {
        get {
            defaults.string(forKey: Self.modeKey)
                .flatMap(AttentionMode.init(rawValue:)) ?? .notify
        }
        set {
            guard newValue != mode else { return }
            defaults.set(newValue.rawValue, forKey: Self.modeKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}

/// Compatibility for existing callers and persisted tests. New UI uses the
/// three-state attention model directly; legacy DND maps to Quiet.
final class DoNotDisturbPreferences {
    static let shared = DoNotDisturbPreferences()
    static let enabledKey = AttentionPreferences.legacyDoNotDisturbKey

    private let attention: AttentionPreferences

    init(defaults: UserDefaults = .standard) {
        attention = AttentionPreferences(defaults: defaults)
    }

    var isEnabled: Bool {
        get { attention.mode == .quiet }
        set { attention.mode = newValue ? .quiet : .notify }
    }

    @discardableResult
    func toggle() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }
}

final class CompletionOutcomePreferences {
    static let shared = CompletionOutcomePreferences()
    static let enabledKey = "showCompletionOutcomes.v1"
    static let didChangeNotification = Notification.Name("CompletionOutcomePreferencesDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledKey: true])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Self.enabledKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    @discardableResult
    func toggle() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }
}
