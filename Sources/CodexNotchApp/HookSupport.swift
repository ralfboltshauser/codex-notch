import AppKit
import CodexNotchCore
import Foundation

struct CodexHookInstaller {
    static let marker = "--codex-notch-local-hook"
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
            (group["hooks"] as? [[String: Any]])?.contains(where: isOurHandler) == true
        }
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
            let cleaned = handlers.filter { !isOurHandler($0) }
            if !cleaned.isEmpty {
                group["hooks"] = cleaned
                cleanedGroups.append(group)
            }
        }

        cleanedGroups.append([
            "hooks": [[
                "type": "command",
                "command": "\(shellQuote(executableURL.path)) \(Self.marker)",
                "timeout": 5,
                "statusMessage": "Saving completion to Codex Notch",
            ]],
        ])
        hooks["Stop"] = cleanedGroups
        root["hooks"] = hooks
        try write(root)
    }

    func uninstall() throws {
        guard FileManager.default.fileExists(atPath: hooksFile.path) else { return }
        var root = try readRoot()
        guard var hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Stop"] as? [[String: Any]] else { return }
        let cleaned: [[String: Any]] = groups.compactMap { group in
            guard var mutable = Optional(group),
                  let handlers = mutable["hooks"] as? [[String: Any]] else { return group }
            let remaining = handlers.filter { !isOurHandler($0) }
            guard !remaining.isEmpty else { return nil }
            mutable["hooks"] = remaining
            return mutable
        }
        if cleaned.isEmpty { hooks.removeValue(forKey: "Stop") }
        else { hooks["Stop"] = cleaned }
        root["hooks"] = hooks
        try write(root)
    }

    private func readRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksFile.path) else { return [:] }
        let data = try Data(contentsOf: hooksFile)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "CodexNotch",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "hooks.json must contain a JSON object"]
            )
        }
        return root
    }

    private func isOurHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(Self.marker) == true
    }

    private func write(_ root: [String: Any]) throws {
        try AppPaths.prepareDirectory(hooksFile.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: hooksFile.path) {
            let backup = hooksFile.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: hooksFile, to: backup)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backup.path
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: hooksFile, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: hooksFile.path
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
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
