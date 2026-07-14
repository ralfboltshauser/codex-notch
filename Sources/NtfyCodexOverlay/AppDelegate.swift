import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let overlay = OverlayController()
    private var subscriber: NtfySubscriber?
    private var hotKeys: GlobalHotKeys?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlay.onOpen = { [weak self] index in self?.openTask(at: index) }
        overlay.onDismiss = { [weak self] index in self?.dismissTask(at: index) }
        overlay.onClear = { [weak self] in self?.store.removeAll() }
        overlay.onSettings = { [weak self] in self?.showOnboarding() }
        store.onChange = { [weak self] tasks in self?.overlay.update(tasks: tasks) }
        overlay.update(tasks: store.tasks)

        hotKeys = GlobalHotKeys { [weak self] action in
            switch action {
            case .toggle:
                if self?.store.tasks.isEmpty == false { self?.overlay.toggle() }
                else { self?.showOnboarding() }
            case .open(let index): self?.openTask(at: index)
            case .dismiss(let index): self?.dismissTask(at: index)
            }
        }

        if let configuration = AppConfiguration.load() {
            configureSubscriber(topic: configuration.topicURL)
        }
        if AppConfiguration.load() == nil
            || !CodexHookInstaller().isInstalled
            || !UserDefaults.standard.bool(forKey: OnboardingWindowController.completionKey) {
            showOnboarding()
        }
    }

    private func configureSubscriber(topic: URL) {
        subscriber?.stop()
        subscriber = NtfySubscriber(topicURL: topic) { [weak self] task in
            self?.store.add(task)
            self?.overlay.showForEvent()
        }
        subscriber?.start()
    }

    private func showOnboarding() {
        onboarding = OnboardingWindowController(configuredTopic: AppConfiguration.load()?.topicURL)
        onboarding?.onConfigured = { [weak self] topic in self?.configureSubscriber(topic: topic) }
        onboarding?.present()
    }

    func applicationWillTerminate(_ notification: Notification) {
        subscriber?.stop()
    }

    private func openTask(at index: Int) {
        guard store.tasks.indices.contains(index) else { return }
        let task = store.tasks[index]
        guard NSWorkspace.shared.open(task.url) else {
            NSSound.beep()
            return
        }
        store.remove(at: index)
        overlay.hide()
    }

    private func dismissTask(at index: Int) {
        _ = store.remove(at: index)
    }
}

@main
enum NtfyCodexOverlayApp {
    static func main() {
        if CommandLine.arguments.contains(CodexHookInstaller.marker) {
            exit(CodexStopHook.run())
        }
        if CommandLine.arguments.contains("--uninstall-hook") {
            do {
                try CodexHookInstaller().uninstall()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--configure"),
           CommandLine.arguments.indices.contains(index + 1),
           let topic = AppConfiguration.normalizedTopicURL(from: CommandLine.arguments[index + 1]) {
            do {
                try AppConfiguration(topicURL: topic).save()
                try CodexHookInstaller().install()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
