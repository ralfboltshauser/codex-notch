import CodexNotchCore
import AppKit
import Foundation
import Security

final class RemoteHostPairer {
    private static let aliasPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
    private static let remoteDirectory = "$HOME/.local/lib/codex-notch"
    private static let remoteScript = "$HOME/.local/lib/codex-notch/codex_notch_remote-v1.py"
    private let store: PairingStore
    private let prepareReceiver: (String) throws -> Void

    init(store: PairingStore, prepareReceiver: @escaping (String) throws -> Void) {
        self.store = store
        self.prepareReceiver = prepareReceiver
    }

    func pair(sshAlias: String, label: String? = nil) throws -> RemoteHost {
        guard Self.isValidAlias(sshAlias) else {
            throw NSError(
                domain: "CodexNotch",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Enter a concrete SSH host alias"]
            )
        }
        guard !store.hosts.contains(where: { $0.sshAlias == sshAlias }) else {
            throw NSError(
                domain: "CodexNotch",
                code: 24,
                userInfo: [NSLocalizedDescriptionKey: "That SSH host is already paired"]
            )
        }
        guard let endpoint = TailscaleDiscovery.localIPv4() else {
            throw NSError(
                domain: "CodexNotch",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Tailscale is not running on this Mac"]
            )
        }
        let scriptData = try bundledRemoteScript()
        try prepareReceiver(endpoint)

        let token = try randomToken()
        let host = RemoteHost(
            id: UUID().uuidString.lowercased(),
            label: CompletionEvent.cleanTitle(label ?? sshAlias),
            sshAlias: sshAlias,
            endpointHost: endpoint,
            createdAt: Date()
        )
        let configuration: [String: Any] = [
            "endpoint_host": endpoint,
            "endpoint_port": Int(TailscaleListener.defaultPort.rawValue),
            "token": token,
            "host_id": host.id,
            "source_name": host.label,
        ]
        let configurationData = try JSONSerialization.data(withJSONObject: configuration)

        try runSSH(
            alias: sshAlias,
            command: "mkdir -p \"$HOME/.local/lib/codex-notch\" && umask 077 && cat > \"\(Self.remoteScript)\" && chmod 700 \"\(Self.remoteScript)\"",
            input: scriptData
        )
        do {
            try store.save(host, token: token)
            try runSSH(
                alias: sshAlias,
                command: "\"\(Self.remoteScript)\" --install-json",
                input: configurationData
            )
            try runSSH(
                alias: sshAlias,
                command: "\"\(Self.remoteScript)\" --ping --ping-attempts 5",
                input: nil
            )
        } catch {
            try? runSSH(
                alias: sshAlias,
                command: Self.remoteUninstallCommand,
                input: scriptData
            )
            try? store.remove(id: host.id)
            throw error
        }
        return host
    }

    func flush(_ host: RemoteHost) {
        DispatchQueue.global(qos: .utility).async {
            try? self.runSSH(
                alias: host.sshAlias,
                command: "\"\(Self.remoteScript)\" --flush",
                input: nil
            )
        }
    }

    func recoverMissingTokens() {
        let missing = store.hostsMissingTokens
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for host in missing {
                guard let data = try? self.runSSHForOutput(
                    alias: host.sshAlias,
                    command: "test -r \"$HOME/.config/codex-notch/remote.json\" && cat \"$HOME/.config/codex-notch/remote.json\""
                ),
                let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                configuration["host_id"] as? String == host.id,
                let token = configuration["token"] as? String,
                (try? self.store.saveRecoveredToken(token.lowercased(), forHostID: host.id)) != nil
                else { continue }

                try? self.runSSH(
                    alias: host.sshAlias,
                    command: "\"\(Self.remoteScript)\" --flush",
                    input: nil
                )
            }
        }
    }

    func unpair(_ host: RemoteHost) throws {
        let scriptData = try bundledRemoteScript()
        try runSSH(
            alias: host.sshAlias,
            command: Self.remoteUninstallCommand,
            input: scriptData
        )
        try store.remove(id: host.id)
    }

    func uninstallAll() throws {
        let hosts = store.hosts
        var failures: [(RemoteHost, Error)] = []
        for host in hosts {
            do { try unpair(host) }
            catch { failures.append((host, error)) }
        }
        guard failures.isEmpty else {
            throw RemoteHostUninstallError(failures: failures, cleanedCount: hosts.count - failures.count)
        }
    }

    func openSession(_ threadID: String) throws {
        guard let canonicalID = UUID(uuidString: threadID)?.uuidString.lowercased() else {
            throw NSError(domain: "CodexNotch", code: 25)
        }
        guard let url = URL(string: "codex://threads/\(canonicalID)"),
              NSWorkspace.shared.open(url) else {
            throw NSError(
                domain: "CodexNotch",
                code: 26,
                userInfo: [NSLocalizedDescriptionKey: "Codex could not open this task"]
            )
        }
    }

    func openTrustReview(for host: RemoteHost) throws {
        guard Self.isValidAlias(host.sshAlias) else {
            throw NSError(
                domain: "CodexNotch",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "The stored SSH host alias is invalid"]
            )
        }
        try AppPaths.prepareDirectory(AppPaths.applicationSupport)
        let commandFile = AppPaths.applicationSupport
            .appendingPathComponent("Review \(host.id) Hook.command")
        let script = "#!/bin/sh\nprintf '\\033]0;Review Remote Codex Hook\\007'\n\necho 'Type /hooks and trust “Queueing completion for Codex Notch”.'\necho\nexec /usr/bin/ssh -t -- \(host.sshAlias) codex\n"
        try Data(script.utf8).write(to: commandFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: commandFile.path
        )
        NSWorkspace.shared.open(commandFile)
    }

    private func runSSH(
        alias: String,
        command: String,
        input: Data?
    ) throws {
        guard Self.isValidAlias(alias) else {
            throw NSError(
                domain: "CodexNotch",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "The stored SSH host alias is invalid"]
            )
        }
        let process = Process()
        let stdin = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "--",
            alias,
            command,
        ]
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        if let input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw NSError(
                domain: "CodexNotch",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: Self.userFacingSSHError(message)]
            )
        }
    }

    static func userFacingSSHError(_ rawMessage: String) -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let conciseMessage: String
        if message.contains("Traceback") {
            conciseMessage = message
                .components(separatedBy: .newlines)
                .reversed()
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? "Remote command failed"
        } else {
            conciseMessage = message
        }
        return conciseMessage.isEmpty
            ? "SSH command failed"
            : String(conciseMessage.prefix(360))
    }

    private func runSSHForOutput(alias: String, command: String) throws -> Data {
        guard Self.isValidAlias(alias) else {
            throw NSError(
                domain: "CodexNotch",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "The stored SSH host alias is invalid"]
            )
        }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "--",
            alias,
            command,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw NSError(
                domain: "CodexNotch",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: Self.userFacingSSHError(message)]
            )
        }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "CodexNotch", code: 23)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidAlias(_ value: String) -> Bool {
        aliasPattern.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private func bundledRemoteScript() throws -> Data {
        guard let script = Bundle.main.resourceURL?
            .appendingPathComponent("remote/codex_notch_remote.py"),
              let data = try? Data(contentsOf: script) else {
            throw NSError(
                domain: "CodexNotch",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "The bundled Ubuntu publisher is missing"]
            )
        }
        return data
    }

    private static let remoteUninstallCommand = """
    set -eu
    temporary=$(mktemp "${TMPDIR:-/tmp}/codex-notch-uninstall.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    cat > "$temporary"
    chmod 700 "$temporary"
    "$temporary" --uninstall
    rm -f "\(remoteScript)"
    rmdir "\(remoteDirectory)" 2>/dev/null || true

    codex_home=${CODEX_HOME:-$HOME/.codex}
    config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    state_home=${XDG_STATE_HOME:-$HOME/.local/state}
    systemd_home="$config_home/systemd/user"
    for hook_file in "$codex_home/hooks.json" "$codex_home/hooks.json.bak"; do
        if [ -f "$hook_file" ] && grep -F -q -- '--codex-notch-remote-hook' "$hook_file"; then
            echo "Codex Notch hook remains in $hook_file" >&2
            exit 1
        fi
    done
    for artifact in \
        "\(remoteScript)" \
        "$config_home/codex-notch" \
        "$state_home/codex-notch" \
        "$systemd_home/codex-notch-flush.service" \
        "$systemd_home/codex-notch-flush.timer"; do
        if [ -e "$artifact" ]; then
            echo "Codex Notch artifact remains at $artifact" >&2
            exit 1
        fi
    done
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet codex-notch-flush.timer \
            || systemctl --user is-active --quiet codex-notch-flush.service; then
            echo "Codex Notch retry service is still active" >&2
            exit 1
        fi
    fi
    """
}

private struct RemoteHostUninstallError: LocalizedError {
    let failures: [(RemoteHost, Error)]
    let cleanedCount: Int

    var errorDescription: String? {
        let names = failures.map { $0.0.label }.joined(separator: ", ")
        let reason = failures.first.map { concise($0.1.localizedDescription) } ?? "SSH cleanup failed"
        let prefix = cleanedCount > 0 ? "Cleaned \(cleanedCount) remote host\(cleanedCount == 1 ? "" : "s"). " : ""
        return "\(prefix)Couldn’t clean \(names): \(reason). The Mac app and local hook were kept; reconnect the host and retry."
    }

    private func concise(_ value: String) -> String {
        value.components(separatedBy: .newlines).first ?? value
    }
}
