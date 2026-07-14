import CodexNotchCore
import AppKit
import Foundation
import Security

final class RemoteHostPairer {
    private static let aliasPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{1,128}$")
    private static let remoteScript = "$HOME/.local/lib/codex-notch/codex_notch_remote-v1.py"
    private let store: PairingStore

    init(store: PairingStore) {
        self.store = store
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
        guard let script = Bundle.main.resourceURL?
            .appendingPathComponent("remote/codex_notch_remote.py"),
              let scriptData = try? Data(contentsOf: script) else {
            throw NSError(
                domain: "CodexNotch",
                code: 22,
                userInfo: [NSLocalizedDescriptionKey: "The bundled Ubuntu publisher is missing"]
            )
        }

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
        try store.save(host, token: token)
        do {
            try runSSH(
                alias: sshAlias,
                command: "\"\(Self.remoteScript)\" --install-json",
                input: configurationData
            )
            try runSSH(alias: sshAlias, command: "\"\(Self.remoteScript)\" --ping", input: nil)
        } catch {
            try? runSSH(
                alias: sshAlias,
                command: "if [ -x \"\(Self.remoteScript)\" ]; then \"\(Self.remoteScript)\" --uninstall; rm -f \"\(Self.remoteScript)\"; fi",
                input: nil
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

    func unpair(_ host: RemoteHost) throws {
        try? runSSH(
            alias: host.sshAlias,
            command: "if [ -x \"\(Self.remoteScript)\" ]; then \"\(Self.remoteScript)\" --uninstall; rm -f \"\(Self.remoteScript)\"; fi",
            input: nil
        )
        try store.remove(id: host.id)
    }

    func openSession(_ threadID: String, on host: RemoteHost) throws {
        guard let canonicalID = UUID(uuidString: threadID)?.uuidString.lowercased() else {
            throw NSError(domain: "CodexNotch", code: 25)
        }
        try AppPaths.prepareDirectory(AppPaths.applicationSupport)
        let commandFile = AppPaths.applicationSupport
            .appendingPathComponent("Resume \(host.id) Session.command")
        let script = "#!/bin/sh\nprintf '\\033]0;Remote Codex Session\\007'\nexec /usr/bin/ssh -t \(host.sshAlias) codex resume \(canonicalID)\n"
        try Data(script.utf8).write(to: commandFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: commandFile.path
        )
        NSWorkspace.shared.open(commandFile)
    }

    func openTrustReview(for host: RemoteHost) throws {
        try AppPaths.prepareDirectory(AppPaths.applicationSupport)
        let commandFile = AppPaths.applicationSupport
            .appendingPathComponent("Review \(host.id) Hook.command")
        let script = "#!/bin/sh\nprintf '\\033]0;Review Remote Codex Hook\\007'\n\necho 'Type /hooks and trust “Queueing completion for Codex Notch”.'\necho\nexec /usr/bin/ssh -t \(host.sshAlias) codex\n"
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
        let process = Process()
        let stdin = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
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
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "CodexNotch",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "SSH command failed" : message]
            )
        }
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
}
