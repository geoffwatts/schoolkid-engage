import Foundation
import Security

/// Stores all account metadata and session secrets in the app's private Keychain access group.
/// No passwords, analytics, cloud synchronization, or school content caches.
public struct KeychainAccountStore {
    private let service: String
    public init(service: String = "au.disengage.accounts") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "accounts"]
    }
    public func load() throws -> [SavedAccount] {
        #if DEBUG && targetEnvironment(simulator)
        if FileManager.default.fileExists(atPath: simulatorFile.path) { return try loadSimulatorAccounts() }
        #endif
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        #if DEBUG && targetEnvironment(simulator)
        if status == errSecItemNotFound || status == errSecMissingEntitlement {
            return try loadSimulatorAccounts()
        }
        #endif
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = item as? Data else { throw SEQTAError.keychain(status) }
        let accounts = try JSONDecoder().decode([SavedAccount].self, from: data)
        #if DEBUG && targetEnvironment(simulator)
        try saveSimulatorAccounts(accounts)
        #endif
        return accounts
    }
    public func save(_ accounts: [SavedAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        #if DEBUG && targetEnvironment(simulator)
        try saveSimulatorAccounts(accounts)
        #endif
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        #if DEBUG && targetEnvironment(simulator)
        if status == errSecMissingEntitlement { return }
        #endif
        if status == errSecItemNotFound {
            var q = query; q.merge(values) { _, new in new }
            let added = SecItemAdd(q as CFDictionary, nil)
            #if DEBUG && targetEnvironment(simulator)
            if added == errSecMissingEntitlement { return }
            #endif
            guard added == errSecSuccess else { throw SEQTAError.keychain(added) }; return
        }
        guard status == errSecSuccess else { throw SEQTAError.keychain(status) }
    }
    #if DEBUG && targetEnvironment(simulator)
    private var simulatorFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalDebugAuth", isDirectory: true).appendingPathComponent(service + ".json")
    }
    private func loadSimulatorAccounts() throws -> [SavedAccount] {
        guard FileManager.default.fileExists(atPath: simulatorFile.path) else { return [] }
        return try JSONDecoder().decode([SavedAccount].self, from: Data(contentsOf: simulatorFile))
    }
    private func saveSimulatorAccounts(_ accounts: [SavedAccount]) throws {
        let directory = simulatorFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(accounts).write(to: simulatorFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: simulatorFile.path)
        var file = simulatorFile; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
    #endif

    public func removeAll() throws {
        #if DEBUG && targetEnvironment(simulator)
        try saveSimulatorAccounts([])
        #endif
        let status = SecItemDelete(query as CFDictionary)
        #if DEBUG && targetEnvironment(simulator)
        if status == errSecMissingEntitlement { return }
        #endif
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SEQTAError.keychain(status) }
    }
}
