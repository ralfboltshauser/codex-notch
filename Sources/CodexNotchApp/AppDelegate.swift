import AppKit
import CodexNotchCore
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let pairings = PairingStore()
    private let overlay = OverlayController()
    private let updater = UpdateCoordinator()
    private var inbox: CompletionInbox?
    private var listener: TailscaleListener?
    private var hotKeys: GlobalHotKeys?
    private var onboarding: OnboardingWindowController?
    private var wakeObserver: NSObjectProtocol?

    private lazy var pairer = RemoteHostPairer(store: pairings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()

        overlay.onOpen = { [weak self] index in self?.openTask(at: index) }
        overlay.onDismiss = { [weak self] index in self?.dismissTask(at: index) }
        overlay.onClear = { [weak self] in self?.store.removeAll() }
        overlay.onSettings = { [weak self] in self?.showOnboarding() }
        overlay.onUpdate = { [weak self] in
            self?.overlay.hide()
            NSApp.activate(ignoringOtherApps: true)
            self?.updater.installAvailableUpdate()
        }
        updater.onAvailabilityChanged = { [weak self] version in
            self?.overlay.setUpdateAvailable(version: version)
        }
        store.onChange = { [weak self] tasks in self?.overlay.update(tasks: tasks) }
        overlay.update(tasks: store.tasks)
        updater.start()

        hotKeys = GlobalHotKeys { [weak self] action in
            switch action {
            case .toggle:
                if self?.overlay.hasContent == true { self?.overlay.toggle() }
                else { self?.showOnboarding() }
            case .open(let index): self?.openTask(at: index)
            case .dismiss(let index): self?.dismissTask(at: index)
            }
        }

        inbox = CompletionInbox { [weak self] event in
            self?.ingest(event) != .rejected
        }
        try? inbox?.start()
        startRemoteListener()
        scheduleRemoteCatchUp()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startRemoteListener()
            self?.scheduleRemoteCatchUp()
            self?.updater.checkForUpdateInformation()
        }

        if !CodexHookInstaller().isInstalled
            || !UserDefaults.standard.bool(forKey: OnboardingWindowController.completionKey) {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inbox?.stop()
        listener?.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func ingest(_ event: CompletionEvent) -> CompletionAcceptance {
        guard let task = CompletedTask(event: event) else { return .rejected }
        do {
            let inserted = try store.add(task)
            if inserted { overlay.showForEvent() }
            return inserted ? .accepted : .duplicate
        } catch {
            return .rejected
        }
    }

    private func startRemoteListener() {
        listener?.stop()
        listener = nil
        guard let address = TailscaleDiscovery.localIPv4() else { return }
        let listener = TailscaleListener(pairings: pairings) { [weak self] event in
            self?.ingest(event) ?? .rejected
        }
        do {
            try listener.start(host: address)
            self.listener = listener
        } catch {
            FileHandle.standardError.write(Data("Could not start Tailscale listener: \(error)\n".utf8))
        }
    }

    private func scheduleRemoteCatchUp() {
        let hosts = pairings.hosts
        guard !hosts.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            hosts.forEach { self.pairer.flush($0) }
        }
    }

    private func showOnboarding() {
        onboarding = OnboardingWindowController(pairings: pairings, pairer: pairer)
        onboarding?.onConnectionsChanged = { [weak self] in
            self?.startRemoteListener()
            self?.scheduleRemoteCatchUp()
        }
        onboarding?.present()
    }

    private func openTask(at index: Int) {
        guard store.tasks.indices.contains(index) else { return }
        let task = store.tasks[index]
        if task.sourceID == "local" {
            guard NSWorkspace.shared.open(task.url) else {
                NSSound.beep()
                return
            }
        } else {
            guard let host = pairings.host(id: task.sourceID) else {
                NSSound.beep()
                return
            }
            do { try pairer.openSession(task.threadID, on: host) }
            catch {
                NSSound.beep()
                return
            }
        }
        store.remove(at: index)
        overlay.hide()
    }

    private func dismissTask(at index: Int) {
        _ = store.remove(at: index)
    }
}

@main
enum CodexNotchApp {
    static func main() {
        if CommandLine.arguments.contains("--uninstall-hook") {
            do {
                try CodexHookInstaller().uninstall()
                try? SMAppService.mainApp.unregister()
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
