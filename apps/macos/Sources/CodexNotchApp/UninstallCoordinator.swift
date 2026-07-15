import Darwin
import Foundation
import ServiceManagement

enum LocalApplicationUninstaller {
    private static let bundleIdentifier = "com.ralfbuilds.CodexNotch"
    private static let legacyBundleIdentifier = "com.ralfbuilds.NtfyCodexOverlay"
    private static let legacyLaunchAgentLabels = [
        "com.ralfbuilds.ntfy-codex-overlay",
        "com.ralfbuilds.ntfy-codex-opener",
    ]

    static func prepare(pairings: PairingStore, bundleURL: URL = Bundle.main.bundleURL) throws {
        guard bundleURL.pathExtension == "app",
              Bundle(url: bundleURL)?.bundleIdentifier == bundleIdentifier else {
            throw NSError(
                domain: "CodexNotch",
                code: 40,
                userInfo: [NSLocalizedDescriptionKey: "Codex Notch is not running from a removable app bundle"]
            )
        }

        try CodexHookInstaller().uninstall()
        try unregisterMainApp()
        try stopLegacyLaunchAgents()
        try pairings.removeAllCredentials()

        let fileManager = FileManager.default
        let parent = bundleURL.deletingLastPathComponent()
        let stagedBundle = parent.appendingPathComponent(
            ".Codex Notch.uninstalling-\(UUID().uuidString).app"
        )
        let artifacts = cleanupArtifacts(bundleURL: bundleURL)
        try fileManager.moveItem(at: bundleURL, to: stagedBundle)
        do {
            try launchCleanupHelper(stagedBundle: stagedBundle, artifacts: artifacts)
        } catch {
            try? fileManager.moveItem(at: stagedBundle, to: bundleURL)
            throw error
        }

        clearDefaults()
    }

    static func removeRegistrationsAndHooks(pairings: PairingStore) throws {
        try CodexHookInstaller().uninstall()
        try unregisterMainApp()
        try stopLegacyLaunchAgents()
        try pairings.removeAllCredentials()
        clearDefaults()
    }

    static func cleanupArtifacts(bundleURL: URL = Bundle.main.bundleURL) -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let applicationSupport = library.appendingPathComponent("Application Support")
        let caches = library.appendingPathComponent("Caches")
        let preferences = library.appendingPathComponent("Preferences")
        let savedState = library.appendingPathComponent("Saved Application State")
        let httpStorage = library.appendingPathComponent("HTTPStorages")
        let webKit = library.appendingPathComponent("WebKit")
        let launchAgents = library.appendingPathComponent("LaunchAgents")

        let candidates = [
            applicationSupport.appendingPathComponent("Codex Notch"),
            applicationSupport.appendingPathComponent("Ntfy Codex Overlay"),
            applicationSupport.appendingPathComponent(bundleIdentifier),
            applicationSupport.appendingPathComponent(legacyBundleIdentifier),
            caches.appendingPathComponent(bundleIdentifier),
            caches.appendingPathComponent(legacyBundleIdentifier),
            preferences.appendingPathComponent("\(bundleIdentifier).plist"),
            preferences.appendingPathComponent("\(legacyBundleIdentifier).plist"),
            savedState.appendingPathComponent("\(bundleIdentifier).savedState"),
            savedState.appendingPathComponent("\(legacyBundleIdentifier).savedState"),
            httpStorage.appendingPathComponent(bundleIdentifier),
            httpStorage.appendingPathComponent(legacyBundleIdentifier),
            webKit.appendingPathComponent(bundleIdentifier),
            webKit.appendingPathComponent(legacyBundleIdentifier),
            library.appendingPathComponent("Logs/ntfy-codex-overlay"),
            launchAgents.appendingPathComponent("com.ralfbuilds.ntfy-codex-overlay.plist"),
            launchAgents.appendingPathComponent("com.ralfbuilds.ntfy-codex-opener.plist"),
            home.appendingPathComponent("Applications/Codex Notch.app"),
            home.appendingPathComponent("Applications/Ntfy Codex Overlay.app"),
        ]
        var seen = Set<String>()
        return candidates.filter { candidate in
            let path = candidate.standardizedFileURL.path
            guard candidate.standardizedFileURL != bundleURL.standardizedFileURL,
                  !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func unregisterMainApp() throws {
        let service = SMAppService.mainApp
        if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    private static func stopLegacyLaunchAgents() throws {
        let domain = "gui/\(getuid())"
        for label in legacyLaunchAgentLabels {
            let target = "\(domain)/\(label)"
            guard try launchctl(["print", target]) == 0 else { continue }
            let status = try launchctl(["bootout", target])
            guard status == 0 else {
                throw NSError(
                    domain: "CodexNotch",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "Could not stop the legacy Codex Notch launch agent \(label)"]
                )
            }
        }
    }

    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func clearDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        UserDefaults.standard.removePersistentDomain(forName: legacyBundleIdentifier)
        UserDefaults.standard.synchronize()
    }

    private static func launchCleanupHelper(stagedBundle: URL, artifacts: [URL]) throws {
        let script = """
        pid=$1
        shift
        attempts=0
        while kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 300 ]; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
        done
        /usr/bin/defaults delete com.ralfbuilds.CodexNotch >/dev/null 2>&1 || true
        /usr/bin/defaults delete com.ralfbuilds.NtfyCodexOverlay >/dev/null 2>&1 || true
        /bin/rm -rf "$@"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            script,
            "codex-notch-uninstaller",
            String(ProcessInfo.processInfo.processIdentifier),
            stagedBundle.path,
        ] + artifacts.map(\.path)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
