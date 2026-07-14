import AppKit
import CodexNotchCore
import Foundation

struct CodexHookInstaller {
    static let marker = "--codex-notch-local-hook"
    private static let legacyMarker = "--codex-hook"
    let hooksFile: URL
    let executableURL: URL

    init(
        hooksFile: URL = AppPaths.hooksFile,
        executableURL: URL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CodexNotchHook")
    ) {
        self.hooksFile = hooksFile
        self.executableURL = executableURL
    }

    var isInstalled: Bool {
        guard let root = try? readRoot(),
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Stop"] as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains(where: isCurrentHandler) == true
        }
    }

    var needsRepair: Bool {
        guard let root = try? readRoot(),
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Stop"] as? [[String: Any]] else { return true }
        let owned = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter(isOwnedHandler)
        guard owned.count == 1, let handler = owned.first else { return true }
        return (handler["command"] as? String) != currentCommand
            || (handler["timeout"] as? Int) != 5
            || (handler["statusMessage"] as? String) != "Saving completion to Codex Notch"
    }

    var hasOwnedInstallation: Bool {
        guard let root = try? readRoot(),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .contains(where: isOwnedHandler)
    }

    func install() throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw NSError(
                domain: "CodexNotch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The bundled Codex hook helper is missing"]
            )
        }

        var root = try readRoot()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let existingGroups = hooks["Stop"] as? [[String: Any]] ?? []
        var cleanedGroups: [[String: Any]] = []

        for var group in existingGroups {
            guard let handlers = group["hooks"] as? [[String: Any]] else {
                cleanedGroups.append(group)
                continue
            }
            let cleaned = handlers.filter { !isOwnedHandler($0) }
            if !cleaned.isEmpty {
                group["hooks"] = cleaned
                cleanedGroups.append(group)
            }
        }

        cleanedGroups.append([
            "hooks": [[
                "type": "command",
                "command": currentCommand,
                "timeout": 5,
                "statusMessage": "Saving completion to Codex Notch",
            ]],
        ])
        hooks["Stop"] = cleanedGroups
        root["hooks"] = hooks
        try write(root)
    }

    func uninstall() throws {
        let stateKeys = try ownedStateKeys()
        try uninstall(from: hooksFile)
        try uninstall(from: hooksFile.appendingPathExtension("bak"))
        try removeHookState(keys: stateKeys)
    }

    private func ownedStateKeys() throws -> Set<String> {
        var keys = Set<String>()
        for file in [hooksFile, hooksFile.appendingPathExtension("bak")] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let data = try Data(contentsOf: file)
            guard containsOwnedMarker(data) else { continue }
            let root = try readRoot(at: file)
            guard let hooks = root["hooks"] as? [String: Any],
                  let groups = hooks["Stop"] as? [[String: Any]] else { continue }
            for (groupIndex, group) in groups.enumerated() {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                for (handlerIndex, handler) in handlers.enumerated() where isOwnedHandler(handler) {
                    keys.insert("\(hooksFile.path):stop:\(groupIndex):\(handlerIndex)")
                }
            }
        }
        return keys
    }

    private func removeHookState(keys: Set<String>) throws {
        guard !keys.isEmpty else { return }
        let configFile = hooksFile.deletingLastPathComponent().appendingPathComponent("config.toml")
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        let original = try String(contentsOf: configFile, encoding: .utf8)
        let targetHeaders = Set(keys.map { "[hooks.state.\(tomlQuoted($0))]" })
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var filtered: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                skipping = targetHeaders.contains(trimmed)
            }
            if !skipping { filtered.append(line) }
        }
        let updated = filtered.joined(separator: "\n")
        guard updated != original else { return }
        try Data(updated.utf8).write(to: configFile, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configFile.path
        )
    }

    private func tomlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func uninstall(from file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let data = try Data(contentsOf: file)
        guard containsOwnedMarker(data) else { return }
        var root = try readRoot(at: file)
        guard var hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Stop"] as? [[String: Any]] else { return }
        let cleaned: [[String: Any]] = groups.compactMap { group in
            guard var mutable = Optional(group),
                  let handlers = mutable["hooks"] as? [[String: Any]] else { return group }
            let remaining = handlers.filter { !isOwnedHandler($0) }
            guard !remaining.isEmpty else { return nil }
            mutable["hooks"] = remaining
            return mutable
        }
        if cleaned.isEmpty { hooks.removeValue(forKey: "Stop") }
        else { hooks["Stop"] = cleaned }
        root["hooks"] = hooks
        try write(root, to: file, backingUpExistingFile: false)
    }

    private func readRoot() throws -> [String: Any] {
        try readRoot(at: hooksFile)
    }

    private func readRoot(at file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "CodexNotch",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "\(file.lastPathComponent) must contain a JSON object"]
            )
        }
        return root
    }

    private func isCurrentHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String) == currentCommand
    }

    private func isOwnedHandler(_ handler: [String: Any]) -> Bool {
        if isCurrentHandler(handler) { return true }
        guard let command = handler["command"] as? String,
              command.contains(Self.legacyMarker) else { return false }
        let status = handler["statusMessage"] as? String
        return command.contains("Ntfy Codex Overlay.app")
            || command.contains("NtfyCodexOverlay")
            || status == "Sending completion to ntfy"
    }

    private func containsOwnedMarker(_ data: Data) -> Bool {
        guard let contents = String(data: data, encoding: .utf8) else { return true }
        return contents.contains(Self.marker)
            || (contents.contains(Self.legacyMarker)
                && (contents.contains("Ntfy Codex Overlay.app")
                    || contents.contains("NtfyCodexOverlay")
                    || contents.contains("Sending completion to ntfy")))
    }

    private func write(
        _ root: [String: Any],
        to file: URL? = nil,
        backingUpExistingFile: Bool = true
    ) throws {
        let file = file ?? hooksFile
        try AppPaths.prepareDirectory(file.deletingLastPathComponent())
        if backingUpExistingFile, FileManager.default.fileExists(atPath: file.path) {
            let backup = file.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: file, to: backup)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backup.path
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private var currentCommand: String { "\(shellQuote(executableURL.path)) \(Self.marker)" }
}

enum CodexHookTrustLauncher {
    static func openCLI() throws {
        let bundled = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        let executable: URL
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            executable = bundled
        } else if let path = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map({ URL(fileURLWithPath: String($0)).appendingPathComponent("codex") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            executable = path
        } else {
            throw NSError(
                domain: "CodexNotch",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Codex CLI was not found"]
            )
        }

        let commandFile = AppPaths.applicationSupport.appendingPathComponent("Review Codex Hook.command")
        try AppPaths.prepareDirectory(AppPaths.applicationSupport)
        let escaped = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "#!/bin/sh\nprintf '\\033]0;Review Codex Hook\\007'\n\necho 'Type /hooks and trust “Saving completion to Codex Notch”.'\necho\nexec \(escaped)\n"
        try Data(script.utf8).write(to: commandFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandFile.path)
        NSWorkspace.shared.open(commandFile)
    }
}
