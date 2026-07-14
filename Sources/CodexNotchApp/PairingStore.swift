import CodexNotchCore
import Foundation

struct RemoteHost: Codable, Equatable {
    let id: String
    let label: String
    let sshAlias: String
    let endpointHost: String
    let createdAt: Date
}

final class PairingStore {
    private let fileURL: URL
    private let tokensFileURL: URL
    private let lock = NSLock()
    private var storedHosts: [RemoteHost]
    private var storedTokens: [String: String]

    init(
        fileURL: URL = AppPaths.pairingsFile,
        tokensFileURL: URL? = nil
    ) {
        self.fileURL = fileURL
        self.tokensFileURL = tokensFileURL
            ?? (fileURL == AppPaths.pairingsFile
                ? AppPaths.pairingTokensFile
                : fileURL.deletingLastPathComponent().appendingPathComponent("remote-host-tokens.json"))
        if let data = try? Data(contentsOf: fileURL),
           let hosts = try? JSONDecoder.codexNotch.decode([RemoteHost].self, from: data) {
            storedHosts = hosts
        } else {
            storedHosts = []
        }
        if let data = try? Data(contentsOf: self.tokensFileURL),
           let tokens = try? JSONDecoder.codexNotch.decode([String: String].self, from: data) {
            storedTokens = tokens.filter { Self.isValidToken($0.value) }
        } else {
            storedTokens = [:]
        }
    }

    var hosts: [RemoteHost] {
        lock.lock()
        defer { lock.unlock() }
        return storedHosts
    }

    func host(id: String) -> RemoteHost? {
        hosts.first { $0.id == id }
    }

    var hostsMissingTokens: [RemoteHost] {
        lock.lock()
        defer { lock.unlock() }
        return storedHosts.filter { storedTokens[$0.id] == nil }
    }

    func save(_ host: RemoteHost, token: String) throws {
        guard Self.isValidToken(token) else { throw invalidTokenError() }
        lock.lock()
        let replacedIDs = storedHosts
            .filter { $0.id != host.id && $0.sshAlias == host.sshAlias }
            .map(\.id)
        var updated = storedHosts.filter { $0.id != host.id && $0.sshAlias != host.sshAlias }
        updated.append(host)
        var updatedTokens = storedTokens
        replacedIDs.forEach { updatedTokens.removeValue(forKey: $0) }
        updatedTokens[host.id] = token
        do {
            try persistTokens(updatedTokens)
            try persistHosts(updated)
            storedHosts = updated
            storedTokens = updatedTokens
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    func saveRecoveredToken(_ token: String, forHostID id: String) throws {
        guard Self.isValidToken(token) else { throw invalidTokenError() }
        lock.lock()
        guard storedHosts.contains(where: { $0.id == id }) else {
            lock.unlock()
            throw NSError(
                domain: "CodexNotch",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "Cannot save a token for an unknown remote host"]
            )
        }
        var updatedTokens = storedTokens
        updatedTokens[id] = token
        do {
            try persistTokens(updatedTokens)
            storedTokens = updatedTokens
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    func remove(id: String) throws {
        lock.lock()
        let updated = storedHosts.filter { $0.id != id }
        var updatedTokens = storedTokens
        updatedTokens.removeValue(forKey: id)
        do {
            try persistHosts(updated)
            try persistTokens(updatedTokens)
            storedHosts = updated
            storedTokens = updatedTokens
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    func host(authenticating candidate: String) -> RemoteHost? {
        lock.lock()
        defer { lock.unlock() }
        for host in storedHosts {
            guard let token = storedTokens[host.id] else { continue }
            if constantTimeEqual(token, candidate) { return host }
        }
        return nil
    }

    private func persistHosts(_ hosts: [RemoteHost]) throws {
        try persist(hosts, to: fileURL)
    }

    private func persistTokens(_ tokens: [String: String]) throws {
        try persist(tokens, to: tokensFileURL)
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) throws {
        try AppPaths.prepareDirectory(url.deletingLastPathComponent())
        let data = try JSONEncoder.codexNotch.encode(value)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.utf8.count == 64
            && token.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
            }
    }

    private func invalidTokenError() -> NSError {
        NSError(
            domain: "CodexNotch",
            code: 41,
            userInfo: [NSLocalizedDescriptionKey: "Remote host token is invalid"]
        )
    }
}
