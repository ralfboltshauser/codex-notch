import Foundation
import AppKit

struct AppConfiguration: Codable, Equatable {
    let topicURL: URL

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ntfy Codex Overlay", isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent("config.json") }

    static func load() -> AppConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: Self.directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: Self.fileURL.path
        )
    }

    static func normalizedTopicURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else { return nil }

        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" {
            return nil
        }
        var path = components.path
        if path.hasSuffix("/json") { path.removeLast(5) }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        components.path = "/" + path
        return components.url
    }

    func subscriptionURL(parameters: [String: String]) -> URL? {
        guard var components = URLComponents(url: topicURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + components.path + "/json"
        var items = components.queryItems ?? []
        for (name, value) in parameters {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        return components.url
    }
}

struct CodexHookInstaller {
    static let marker = "--codex-hook"
    let hooksFile: URL
    let executableURL: URL

    init(
        hooksFile: URL = CodexHookInstaller.defaultHooksFile,
        executableURL: URL = Bundle.main.executableURL!
    ) {
        self.hooksFile = hooksFile
        self.executableURL = executableURL
    }

    static var defaultHooksFile: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("hooks.json")
    }

    var isInstalled: Bool {
        guard let root = readRoot(),
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Stop"] as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains(where: isOurHandler) == true
        }
    }

    func install() throws {
        var root = readRoot() ?? [:]
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

        let command = "\(shellQuote(executableURL.path)) \(Self.marker)"
        cleanedGroups.append([
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": 10,
                "statusMessage": "Sending completion to ntfy",
            ]],
        ])
        hooks["Stop"] = cleanedGroups
        root["hooks"] = hooks

        try write(root)
    }

    func uninstall() throws {
        guard var root = readRoot(),
              var hooks = root["hooks"] as? [String: Any],
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

    private func readRoot() -> [String: Any]? {
        guard let data = try? Data(contentsOf: hooksFile),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }
        return root
    }

    private func isOurHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(Self.marker) == true
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: hooksFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: hooksFile.path) {
            let backup = hooksFile.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: hooksFile, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: hooksFile, options: [.atomic])
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum CodexStopHook {
    private struct Input: Decodable {
        let session_id: String
        let turn_id: String?
        let cwd: String?
        let hook_event_name: String?
    }

    static func run() -> Int32 {
        do {
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            let input = try JSONDecoder().decode(Input.self, from: inputData)
            guard input.hook_event_name == nil || input.hook_event_name == "Stop",
                  let configuration = AppConfiguration.load(),
                  NtfyEventParser.validCodexThreadURL("codex://threads/\(input.session_id)") != nil
            else { return 0 }

            let title = lookupTitle(sessionID: input.session_id)
                ?? input.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Codex task"
            let request = publishRequest(
                sessionID: input.session_id,
                title: title,
                topicURL: configuration.topicURL
            )
            try publish(request)
        } catch {
            log("Hook delivery failed: \(error.localizedDescription)")
        }
        // Notifications must never block or fail the Codex turn.
        return 0
    }

    static func notificationPayload(
        sessionID: String,
        title: String,
        message: String = "Task finished"
    ) -> [String: Any] {
        let deepLink = "codex://threads/\(sessionID)"
        return [
            "title": "Codex finished: \(title)",
            "message": message,
            "tags": ["computer", "white_check_mark"],
            "click": deepLink,
            "actions": [[
                "action": "view", "label": "Open Codex task", "clear": true, "url": deepLink,
            ]],
        ]
    }

    static func publishRequest(sessionID: String, title: String, topicURL: URL) -> URLRequest {
        let deepLink = "codex://threads/\(sessionID)"
        let encodedTitle = Data("Codex finished: \(title)".utf8).base64EncodedString()
        var request = URLRequest(url: topicURL, timeoutInterval: 7)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("=?UTF-8?B?\(encodedTitle)?=", forHTTPHeaderField: "Title")
        request.setValue("computer,white_check_mark", forHTTPHeaderField: "Tags")
        request.setValue(deepLink, forHTTPHeaderField: "Click")
        request.setValue(
            "view, Open Codex task, \(deepLink), clear=true",
            forHTTPHeaderField: "Actions"
        )
        request.setValue("ntfy-codex-overlay-hook/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("Task finished".utf8)
        return request
    }

    private static func lookupTitle(sessionID: String) -> String? {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        for line in data.split(separator: 0x0A).reversed() {
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  value["id"] as? String == sessionID else { continue }
            return (value["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func publish(_ request: URLRequest) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error> = .success(())
        URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                result = .failure(NSError(
                    domain: "NtfyCodexOverlay",
                    code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: "ntfy rejected the notification"]
                ))
                return
            }
        }.resume()
        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            throw NSError(
                domain: "NtfyCodexOverlay",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "ntfy request timed out"]
            )
        }
        try result.get()
    }

    private static func log(_ text: String) {
        let directory = AppConfiguration.directoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("hook.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
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
                domain: "NtfyCodexOverlay",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Codex CLI was not found"]
            )
        }

        let commandFile = AppConfiguration.directoryURL.appendingPathComponent("Review Codex Hook.command")
        try FileManager.default.createDirectory(
            at: AppConfiguration.directoryURL,
            withIntermediateDirectories: true
        )
        let escaped = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "#!/bin/sh\nprintf '\\033]0;Review Codex Hook\\007'\n\necho 'When Codex opens, type /hooks and trust “Sending completion to ntfy”.'\necho\nexec \(escaped)\n"
        try Data(script.utf8).write(to: commandFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandFile.path)
        NSWorkspace.shared.open(commandFile)
    }
}
