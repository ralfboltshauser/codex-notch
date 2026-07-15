import AppKit
import CodexNotchCore
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let activeStore = ActiveTaskStore()
    private let activePreferences = ActiveTaskPreferences.shared
    private let appServerObserver = AppServerObserver()
    private let pairings = PairingStore()
    private let overlay = OverlayController(
        automaticOpenAllowed: { !DoNotDisturbPreferences.shared.isEnabled }
    )
    private let notificationSounds = NotificationSoundPlayer()
    private let updater = UpdateCoordinator()
    private let usageMonitor = CodexUsageMonitor()
    private let notchHoverMonitor = NotchHoverMonitor()
    private var inbox: CompletionInbox?
    private var listener: TailscaleListener?
    private var listenerAddress: String?
    private var hotKeys: GlobalHotKeys?
    private var onboarding: OnboardingWindowController?
    private var wakeObserver: NSObjectProtocol?
    private var activePreferenceObserver: NSObjectProtocol?
    private var activeReaper: Timer?
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

    private lazy var remoteHealthMonitor = RemoteHostHealthMonitor(
        pairings: pairings,
        pairer: pairer
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()

        overlay.onOpen = { [weak self] task in self?.activate(task) ?? false }
        overlay.onOpenActive = { [weak self] task in self?.activate(task) ?? false }
        overlay.onOpenFinished = { [weak self] task in self?.removeOpenedTask(task) }
        overlay.onDismiss = { [weak self] index in self?.dismissTask(at: index) }
        overlay.onClear = { [weak self] in self?.store.removeAll() }
        overlay.onSettings = { [weak self] in self?.showOnboarding() }
        overlay.onConnections = { [weak self] in self?.showOnboarding(showConnections: true) }
        overlay.onToggleActiveTasks = { [weak self] in self?.toggleActiveTasks() }
        overlay.onUpdate = { [weak self] in
            self?.overlay.hide()
            NSApp.activate(ignoringOtherApps: true)
            self?.updater.installAvailableUpdate()
        }
        updater.onAvailabilityChanged = { [weak self] version in
            self?.overlay.setUpdateAvailable(version: version)
        }
        usageMonitor.onChange = { [weak self] state in
            self?.overlay.setUsageState(state)
        }
        overlay.onRefreshUsage = { [weak self] in self?.usageMonitor.refresh() }
        store.onChange = { [weak self] tasks in self?.overlay.update(tasks: tasks) }
        overlay.update(tasks: store.tasks)
        activeStore.onChange = { [weak self] tasks in
            guard let self else { return }
            self.overlay.update(activeTasks: tasks, visible: self.activePreferences.isVisible)
        }
        overlay.update(activeTasks: activeStore.tasks, visible: activePreferences.isVisible)
        updater.start()
        usageMonitor.start()

        notchHoverMonitor.onActivate = { [weak self] screen in
            self?.usageMonitor.refresh()
            self?.overlay.showFromNotchHover(on: screen)
        }
        notchHoverMonitor.start()

        hotKeys = GlobalHotKeys { [weak self] action in
            switch action {
            case .toggle:
                self?.usageMonitor.refresh()
                self?.overlay.toggle()
            case .open(let index): self?.overlay.openTask(at: index, animated: false)
            case .dismiss(let index): self?.overlay.dismissTask(at: index, animated: false)
            case .settings: self?.overlay.openSettings()
            case .toggleActiveTasks: self?.toggleActiveTasks()
            }
        }
        overlay.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.hotKeys?.setSettingsShortcutEnabled(visible)
            if visible { self.remoteHealthMonitor.refresh() }
        }

        inbox = CompletionInbox { [weak self] event in
            self?.ingest(event) != .rejected
        }
        try? inbox?.start()
        _ = try? startRemoteListener()
        pairer.recoverMissingTokens()
        scheduleRemoteCatchUp()
        remoteHealthMonitor.onChange = { [weak self] snapshot in
            self?.overlay.setRemoteHostHealth(snapshot)
            self?.onboarding?.updateRemoteHealth(snapshot)
        }
        remoteHealthMonitor.start()
        appServerObserver.onSnapshot = { [weak self] sourceID, sourceLabel, snapshot in
            _ = self?.activeStore.replace(
                sourceID: sourceID,
                sourceLabel: sourceLabel,
                snapshot: snapshot
            )
        }
        appServerObserver.start()
        activePreferenceObserver = NotificationCenter.default.addObserver(
            forName: ActiveTaskPreferences.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.overlay.update(activeTasks: self.activeStore.tasks, visible: self.activePreferences.isVisible)
        }
        activeReaper = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.activeStore.reapStaleSources()
        }
        let localInstaller = CodexHookInstaller()
        if localInstaller.hasOwnedInstallation, localInstaller.needsRepair {
            do {
                try localInstaller.install()
                UserDefaults.standard.set(false, forKey: OnboardingWindowController.completionKey)
            } catch {
                NSLog("Could not repair the Codex Notch hook: %@", error.localizedDescription)
            }
        }
        pairer.repairAllInBackground { [weak self] in
            self?.remoteHealthMonitor.refresh(force: true)
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = try? self?.startRemoteListener(force: true)
            self?.scheduleRemoteCatchUp()
            self?.remoteHealthMonitor.refresh(force: true)
            self?.updater.checkForUpdateInformation()
            self?.usageMonitor.refresh()
        }

        if !CodexHookInstaller().isInstalled
            || !UserDefaults.standard.bool(forKey: OnboardingWindowController.completionKey) {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        inbox?.stop()
        listener?.stop()
        remoteHealthMonitor.stop()
        appServerObserver.stop()
        usageMonitor.stop()
        notchHoverMonitor.stop()
        activeReaper?.invalidate()
        if let activePreferenceObserver { NotificationCenter.default.removeObserver(activePreferenceObserver) }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func ingest(_ event: CompletionEvent) -> CompletionAcceptance {
        guard let task = CompletedTask(event: event) else { return .rejected }
        activeStore.remove(threadID: event.threadID, sourceID: event.sourceID)
        do {
            let inserted = try store.add(task)
            if inserted {
                usageMonitor.refresh()
                notificationSounds.playSelected()
                overlay.showForEvent(triggeringEventID: task.eventID)
            }
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
        let listener = TailscaleListener(
            pairings: pairings,
            activeDelivery: { [weak self] host, snapshot in
                self?.activeStore.replace(
                    sourceID: host.id,
                    sourceLabel: host.label,
                    snapshot: snapshot
                ) ?? false
            },
            delivery: { [weak self] event in self?.ingest(event) ?? .rejected }
        )
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

    private func showOnboarding(showConnections: Bool = false) {
        if let onboarding {
            onboarding.updateRemoteHealth(remoteHealthMonitor.snapshot)
            if showConnections {
                onboarding.presentConnections()
            } else {
                onboarding.present()
            }
            remoteHealthMonitor.refresh()
            return
        }
        onboarding = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            notificationSounds: notificationSounds
        )
        onboarding?.onConnectionsChanged = { [weak self] in
            _ = try? self?.startRemoteListener()
            self?.scheduleRemoteCatchUp()
            self?.remoteHealthMonitor.refresh(force: true)
            guard let self else { return }
            let currentIDs = Set(self.pairings.hosts.map(\.id))
            self.activeStore.tasks
                .map(\.sourceID)
                .filter { $0 != "local" && !currentIDs.contains($0) }
                .forEach { self.activeStore.removeSource($0) }
        }
        onboarding?.onRefreshConnections = { [weak self] in
            self?.remoteHealthMonitor.refresh(force: true)
        }
        onboarding?.onCheckForUpdates = { [weak self] in
            self?.updater.checkForUpdates()
        }
        onboarding?.onThemePreviewVisibilityChanged = { [weak self] visible, screen in
            self?.overlay.setThemePreviewVisible(visible, on: screen)
        }
        onboarding?.onUninstall = { [weak self] completion in
            self?.uninstall(completion: completion)
        }
        onboarding?.updateRemoteHealth(remoteHealthMonitor.snapshot)
        if showConnections {
            onboarding?.presentConnections()
        } else {
            onboarding?.present()
        }
        remoteHealthMonitor.refresh()
    }

    @objc func openSettings(_ sender: Any?) {
        overlay.hide(immediately: true)
        showOnboarding()
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
                    completion(.success(Void()))
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

    private func activate(_ task: ActiveTask) -> Bool {
        guard let url = task.url, NSWorkspace.shared.open(url) else {
            NSSound.beep()
            return false
        }
        return true
    }

    private func toggleActiveTasks() {
        _ = activePreferences.toggle()
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
        if CommandLine.arguments.contains("--validate-packaged-resources") {
            guard !ChangelogCatalog.releases.isEmpty else {
                FileHandle.standardError.write(Data("Packaged changelog could not be loaded\n".utf8))
                exit(1)
            }
            return
        }
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
