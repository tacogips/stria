import Foundation
import Security

public protocol CredentialSynchronizationStore: CredentialStore {
  var isSynchronizationEnabled: Bool { get }
  func setSynchronizationEnabled(_ enabled: Bool) throws
}

protocol CredentialSyncPreference: Sendable {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool)
}

private struct DefaultCredentialSyncPreference: CredentialSyncPreference {
  private let key = "syncAPIKeysWithICloud"
  var isEnabled: Bool {
    if let value = UserDefaults.standard.object(forKey: key) as? Bool { return value }
    #if os(iOS)
    return true
    #else
    return false
    #endif
  }
  func setEnabled(_ enabled: Bool) { UserDefaults.standard.set(enabled, forKey: key) }
}

/// Vendor secrets sync only through iCloud Keychain, never the document sync folder.
/// The lock serializes key writes and scope migration across concurrent service calls.
public final class KeychainCredentialStore: CredentialSynchronizationStore, @unchecked Sendable {
  public static let service = "me.tacogips.stria.apikey"
  private let executor: any CredentialKeychainExecuting
  private let preference: any CredentialSyncPreference
  private let lock = NSLock()

  public convenience init() {
    self.init(executor: SecurityCredentialKeychainExecutor(), preference: DefaultCredentialSyncPreference())
  }

  init(executor: any CredentialKeychainExecuting, preference: any CredentialSyncPreference) {
    self.executor = executor
    self.preference = preference
  }

  public var isSynchronizationEnabled: Bool { lock.withLock { preference.isEnabled } }

  public func read(vendor: String) throws -> String? {
    try lock.withLock {
      let sync = preference.isEnabled
      if let value = try read(vendor: vendor, sync: sync) { return value }
      guard sync, let legacy = try read(vendor: vendor, sync: false) else { return nil }
      // Upgrade existing device-only keys on first use; never delete before copying.
      try write(legacy, vendor: vendor, sync: true)
      try delete(vendor: vendor, sync: false)
      return legacy
    }
  }

  public func write(_ value: String, vendor: String) throws {
    try lock.withLock {
      guard !value.isEmpty else { try deleteAllScopes(vendor: vendor); return }
      let sync = preference.isEnabled
      try write(value, vendor: vendor, sync: sync)
      // Remove stale fallback data after a successful replacement.
      if sync { try delete(vendor: vendor, sync: false) }
    }
  }

  public func delete(vendor: String) throws {
    try lock.withLock { try deleteAllScopes(vendor: vendor) }
  }

  public func setSynchronizationEnabled(_ enabled: Bool) throws {
    try lock.withLock {
      let current = preference.isEnabled
      guard current != enabled else { return }
      // Copy all keys before committing the preference. On failure the old scope
      // remains authoritative and no source key has been removed.
      for vendor in KnownVendors.apiKeyVendors.sorted() {
        if let value = try read(vendor: vendor, sync: current) {
          try write(value, vendor: vendor, sync: enabled)
        }
      }
      preference.setEnabled(enabled)
      // Keep cloud copies when disabling sync on this device. Explicit Delete
      // removes both scopes; merely disabling sync must not erase other devices.
      if enabled {
        for vendor in KnownVendors.apiKeyVendors.sorted() { try delete(vendor: vendor, sync: false) }
      }
    }
  }

  private func read(vendor: String, sync: Bool) throws -> String? {
    var query = query(vendor: vendor, sync: sync)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, result) = executor.copyMatching(query)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
      throw ServiceError.unavailable("Could not decode the saved API key")
    }
    return value
  }

  private func write(_ value: String, vendor: String, sync: Bool) throws {
    let query = query(vendor: vendor, sync: sync)
    let attributes: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: sync ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    var item = query
    item.merge(attributes) { _, new in new }
    let status = executor.add(item)
    if status == errSecDuplicateItem { try check(executor.update(query, attributes: attributes)) } else { try check(status) }
  }

  private func deleteAllScopes(vendor: String) throws {
    try delete(vendor: vendor, sync: false)
    try delete(vendor: vendor, sync: true)
  }

  private func delete(vendor: String, sync: Bool) throws {
    let status = executor.delete(query(vendor: vendor, sync: sync))
    if status != errSecItemNotFound { try check(status) }
  }

  private func query(vendor: String, sync: Bool) -> [String: Any] {
    var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: Self.service,
                                kSecAttrAccount as String: vendor,
                                kSecAttrSynchronizable as String: sync]
    #if os(macOS)
    if sync, let group = Bundle.main.object(forInfoDictionaryKey: "StriaSharedKeychainAccessGroup") as? String {
      query[kSecAttrAccessGroup as String] = group
    }
    #endif
    return query
  }

  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw ServiceError.unavailable("Keychain operation failed (status \(status))") }
  }
}

protocol CredentialKeychainExecuting: Sendable {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?)
  func add(_ item: [String: Any]) -> OSStatus
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

private struct SecurityCredentialKeychainExecutor: CredentialKeychainExecuting {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result)
  }
  func add(_ item: [String: Any]) -> OSStatus { SecItemAdd(item as CFDictionary, nil) }
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }
  func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}
