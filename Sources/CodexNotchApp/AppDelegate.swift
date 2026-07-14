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
    private var listenerAddress: String?
    private var hotKeys: GlobalHotKeys?
    private var onboarding: OnboardingWindowController?
    private var wakeObserver: NSObjectProtocol?
    private var uninstalling = false

    private lazy var pairer = RemoteHostPairer(store: pairings) { [weak self] endpoint in
        guard let self else {
            throw NSError(
                domain: "CodexNotch",
                code: 33,
                userInfo: [NSLocalizedDescriptionKey: "Codex Notch closed before pairing could start"]
            )
        }
        let startReceiver: (Bool) throws -> TailscaleListener = { force in
            if Thread.isMainThread {
                return try self.startRemoteListener(at: endpoint, force: force)
            }
            return try DispatchQueue.main.sync {
                try self.startRemoteListener(at: endpoint, force: force)
            }
        }
        let receiver = try startReceiver(false)
        do {
            try receiver.waitUntilReady()
        } catch {
            let replacement = try startReceiver(true)
            try replacement.waitUntilReady()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()

        overlay.onOpen = { [weak self] task in self?.activate(task) ?? false }
        overlay.onOpenFinished = { [weak self] task in self?.removeOpenedTask(task) }
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
            case .open(let index): self?.overlay.openTask(at: index, animated: false)
            case .dismiss(let index): self?.overlay.dismissTask(at: index, animated: false)
            }
        }

        inbox = CompletionInbox { [weak self] event in
            self?.ingest(event) != .rejected
        }
        try? inbox?.start()
        _ = try? startRemoteListener()
        pairer.recoverMissingTokens()
        scheduleRemoteCatchUp()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = try? self?.startRemoteListener(force: true)
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

    private func startRemoteListener(
        at requestedAddress: String? = nil,
        force: Bool = false
    ) throws -> TailscaleListener {
        let address: String
        if let requestedAddress {
            address = requestedAddress
        } else if let discoveredAddress = TailscaleDiscovery.localIPv4() {
            address = discoveredAddress
        } else {
            throw NSError(
                domain: "CodexNotch",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Tailscale is not running on this Mac"]
            )
        }
        if !force, let listener, listenerAddress == address { return listener }

        listener?.stop()
        listener = nil
        listenerAddress = nil
        let listener = TailscaleListener(pairings: pairings) { [weak self] event in
            self?.ingest(event) ?? .rejected
        }
        do {
            try listener.start(host: address)
            self.listener = listener
            listenerAddress = address
            return listener
        } catch {
            listener.stop()
            throw error
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
        if let onboarding {
            onboarding.present()
            return
        }
        onboarding = OnboardingWindowController(pairings: pairings, pairer: pairer)
        onboarding?.onConnectionsChanged = { [weak self] in
            _ = try? self?.startRemoteListener()
            self?.scheduleRemoteCatchUp()
        }
        onboarding?.onUninstall = { [weak self] completion in
            self?.uninstall(completion: completion)
        }
        onboarding?.present()
    }

    private func uninstall(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !uninstalling else {
            completion(.failure(NSError(
                domain: "CodexNotch",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: "An uninstall is already in progress"]
            )))
            return
        }
        uninstalling = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.pairer.uninstallAll()
            } catch {
                DispatchQueue.main.async {
                    self.uninstalling = false
                    completion(.failure(error))
                }
                return
            }
            DispatchQueue.main.async {
                do {
                    try LocalApplicationUninstaller.prepare(pairings: self.pairings)
                    completion(.success(()))
                    NSApp.terminate(nil)
                } catch {
                    self.uninstalling = false
                    completion(.failure(error))
                }
            }
        }
    }

    private func activate(_ task: CompletedTask) -> Bool {
        if task.sourceID == "local" {
            guard NSWorkspace.shared.open(task.url) else {
                NSSound.beep()
                return false
            }
        } else {
            guard pairings.host(id: task.sourceID) != nil else {
                NSSound.beep()
                return false
            }
            do { try pairer.openSession(task.threadID) }
            catch {
                NSSound.beep()
                return false
            }
        }
        return true
    }

    private func removeOpenedTask(_ task: CompletedTask) {
        guard let index = store.tasks.firstIndex(where: { $0.eventID == task.eventID }) else { return }
        store.remove(at: index)
    }

    private func dismissTask(at index: Int) {
        _ = store.remove(at: index)
    }
}

@main
enum CodexNotchApp {
    static func main() {
        if CommandLine.arguments.contains("--prepare-uninstall") {
            let pairings = PairingStore()
            let pairer = RemoteHostPairer(store: pairings) { _ in }
            do {
                try pairer.uninstallAll()
                try LocalApplicationUninstaller.removeRegistrationsAndHooks(pairings: pairings)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
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
