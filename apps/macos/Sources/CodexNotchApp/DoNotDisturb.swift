import Foundation

final class DoNotDisturbPreferences {
    static let shared = DoNotDisturbPreferences()
    static let enabledKey = "doNotDisturbEnabled.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledKey: false])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    @discardableResult
    func toggle() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }
}
