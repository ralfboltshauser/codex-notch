import CodexNotchCore
import Foundation
import Security

struct RemoteHost: Codable, Equatable {
    let id: String
    let label: String
    let sshAlias: String
    let endpointHost: String
    let createdAt: Date
}

enum KeychainStore {
    private static let service = "com.ralfbuilds.codex-notch.remote-host"

    static func set(_ value: String, account: String) throws {
        delete(account: account)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    static func get(account: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil).map { $0 as String }
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message ?? "Keychain error"]
        )
    }
}

final class PairingStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var storedHosts: [RemoteHost]

    init(fileURL: URL = AppPaths.pairingsFile) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let hosts = try? JSONDecoder.codexNotch.decode([RemoteHost].self, from: data) {
            storedHosts = hosts
        } else {
            storedHosts = []
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

    func save(_ host: RemoteHost, token: String) throws {
        try KeychainStore.set(token, account: host.id)
        lock.lock()
        let replacedIDs = storedHosts
            .filter { $0.id != host.id && $0.sshAlias == host.sshAlias }
            .map(\.id)
        var updated = storedHosts.filter { $0.id != host.id && $0.sshAlias != host.sshAlias }
        updated.append(host)
        do {
            try persist(updated)
            storedHosts = updated
            lock.unlock()
            replacedIDs.forEach { KeychainStore.delete(account: $0) }
        } catch {
            lock.unlock()
            KeychainStore.delete(account: host.id)
            throw error
        }
    }

    func remove(id: String) throws {
        lock.lock()
        let updated = storedHosts.filter { $0.id != id }
        do {
            try persist(updated)
            storedHosts = updated
            lock.unlock()
            KeychainStore.delete(account: id)
        } catch {
            lock.unlock()
            throw error
        }
    }

    func host(authenticating candidate: String) -> RemoteHost? {
        for host in hosts {
            guard let token = KeychainStore.get(account: host.id) else { continue }
            if constantTimeEqual(token, candidate) { return host }
        }
        return nil
    }

    private func persist(_ hosts: [RemoteHost]) throws {
        try AppPaths.prepareDirectory(fileURL.deletingLastPathComponent())
        let data = try JSONEncoder.codexNotch.encode(hosts)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
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
}
