import Foundation
import Security

public struct KeychainError: Error, LocalizedError, Equatable {
    public let status: Int32
    public init(_ status: Int32) { self.status = status }
    public var errorDescription: String? { "Could not access saved accounts (Keychain \(status))." }
}

/// One secret blob in the app's private Keychain access group, readable only while the device is unlocked and never
/// synced or backed up. Debug simulator builds without the Keychain entitlement fall back to a private file.
public struct KeychainItem: Sendable {
    public let service: String
    public let account: String
    /// The debug simulator fallback's file name.
    let fileName: String
    public init(service: String, account: String, fileName: String? = nil) {
        self.service = service; self.account = account; self.fileName = fileName ?? "\(service).\(account).json"
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// The stored data, or nil if nothing has been saved.
    public func load() throws -> Data? {
        #if DEBUG && targetEnvironment(simulator)
        if FileManager.default.fileExists(atPath: simulatorFile.path) { return try Data(contentsOf: simulatorFile) }
        #endif
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        #if DEBUG && targetEnvironment(simulator)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        #endif
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status) }
        #if DEBUG && targetEnvironment(simulator)
        try saveSimulatorFile(data)
        #endif
        return data
    }

    public func save(_ data: Data) throws {
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        #if DEBUG && targetEnvironment(simulator)
        try saveSimulatorFile(data)
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
            guard added == errSecSuccess else { throw KeychainError(added) }; return
        }
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func remove() throws {
        #if DEBUG && targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: simulatorFile)
        #endif
        let status = SecItemDelete(query as CFDictionary)
        #if DEBUG && targetEnvironment(simulator)
        if status == errSecMissingEntitlement { return }
        #endif
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    #if DEBUG && targetEnvironment(simulator)
    private var simulatorFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalDebugAuth", isDirectory: true).appendingPathComponent(fileName)
    }
    private func saveSimulatorFile(_ data: Data) throws {
        let directory = simulatorFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: simulatorFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: simulatorFile.path)
        var file = simulatorFile; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
    #endif
}
