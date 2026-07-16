import Foundation

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case connect
    case practice
    case ready

    var eyebrow: String {
        switch self {
        case .welcome: return "WELCOME"
        case .connect: return "CONNECT"
        case .practice: return "MAKE IT MUSCLE MEMORY"
        case .ready: return "READY"
        }
    }
}

struct OnboardingJourney: Equatable {
    private(set) var step: OnboardingStep = .welcome
    private(set) var hookInstalled: Bool
    private(set) var hookTrusted: Bool
    private(set) var openedNotch = false

    init(hookInstalled: Bool, hookTrusted: Bool) {
        self.hookInstalled = hookInstalled
        self.hookTrusted = hookTrusted
    }

    var progress: Double {
        Double(step.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    var canAdvance: Bool {
        switch step {
        case .connect: return hookInstalled && hookTrusted
        case .welcome, .practice, .ready: return true
        }
    }

    mutating func updateHook(installed: Bool, trusted: Bool) {
        hookInstalled = installed
        hookTrusted = trusted
    }

    mutating func markNotchOpened() {
        openedNotch = true
    }

    @discardableResult
    mutating func advance() -> OnboardingStep {
        guard canAdvance,
              let next = OnboardingStep(rawValue: step.rawValue + 1) else { return step }
        step = next
        return step
    }

    @discardableResult
    mutating func goBack() -> OnboardingStep {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return step }
        step = previous
        return step
    }
}
