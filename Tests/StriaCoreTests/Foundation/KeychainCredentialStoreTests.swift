import Foundation
import Security
@testable import StriaCore
import Testing

@Suite struct KeychainCredentialStoreTests {
  @Test func savesSynchronizableKeysAndMigratesLegacyKeys() throws {
    let executor = MemoryKeychainExecutor()
    let preference = MemorySyncPreference(true)
    let store = KeychainCredentialStore(executor: executor, preference: preference)
    executor.seed("legacy", vendor: "openai", sync: false)
    #expect(try store.read(vendor: "openai") == "legacy")
    #expect(executor.value("openai", sync: false) == nil)
    #expect(executor.value("openai", sync: true) == "legacy")
    #expect(executor.lastAccessibility == kSecAttrAccessibleAfterFirstUnlock as String)
    try store.write("replacement", vendor: "openai")
    #expect(try store.read(vendor: "openai") == "replacement")
  }

  @Test func disablingSyncKeepsCloudCopyAndDeleteRemovesBothScopes() throws {
    let executor = MemoryKeychainExecutor()
    let preference = MemorySyncPreference(true)
    let store = KeychainCredentialStore(executor: executor, preference: preference)
    try store.write("cloud", vendor: "openai")
    try store.setSynchronizationEnabled(false)
    #expect(!store.isSynchronizationEnabled)
    #expect(executor.value("openai", sync: true) == "cloud")
    #expect(executor.value("openai", sync: false) == "cloud")
    #expect(executor.lastAccessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    try store.write("local replacement", vendor: "openai")
    #expect(try store.read(vendor: "openai") == "local replacement")
    try store.setSynchronizationEnabled(true)
    #expect(try store.read(vendor: "openai") == "local replacement")
    #expect(executor.value("openai", sync: false) == nil)
    try store.delete(vendor: "openai")
    #expect(try store.read(vendor: "openai") == nil)
    #expect(executor.value("openai", sync: false) == nil)
  }

  @Test func failedMigrationKeepsPreferenceAndOriginalKeys() throws {
    let executor = MemoryKeychainExecutor()
    let preference = MemorySyncPreference(false)
    let store = KeychainCredentialStore(executor: executor, preference: preference)
    executor.seed("first", vendor: "anthropic", sync: false)
    executor.seed("second", vendor: "openai", sync: false)
    executor.rejectVendor = "openai"
    #expect(throws: ServiceError.self) { try store.setSynchronizationEnabled(true) }
    #expect(!store.isSynchronizationEnabled)
    #expect(try store.read(vendor: "anthropic") == "first")
    #expect(try store.read(vendor: "openai") == "second")
    executor.rejectVendor = nil
    try store.setSynchronizationEnabled(true)
    #expect(try store.read(vendor: "openai") == "second")
  }

  @Test func localOnlyReadDoesNotRetrieveRemoteSecrets() throws {
    let executor = MemoryKeychainExecutor()
    executor.seed("remote", vendor: "gemini", sync: true)
    let store = KeychainCredentialStore(executor: executor, preference: MemorySyncPreference(false))
    #expect(try store.read(vendor: "gemini") == nil)
    try store.delete(vendor: "gemini")
    #expect(executor.value("gemini", sync: true) == nil)
  }
}

// Store operations serialize this test executor; tests never touch the real Keychain.
private final class MemorySyncPreference: CredentialSyncPreference, @unchecked Sendable {
  var isEnabled: Bool
  init(_ enabled: Bool) { isEnabled = enabled }
  func setEnabled(_ enabled: Bool) { isEnabled = enabled }
}

private final class MemoryKeychainExecutor: CredentialKeychainExecuting, @unchecked Sendable {
  private var values: [String: Data] = [:]
  var rejectVendor: String?
  var lastAccessibility: String?
  private func key(_ vendor: String, _ sync: Bool) -> String { "\(vendor):\(sync)" }
  private func key(_ query: [String: Any]) -> String {
    key(query[kSecAttrAccount as String] as? String ?? "", query[kSecAttrSynchronizable as String] as? Bool ?? false)
  }
  func seed(_ value: String, vendor: String, sync: Bool) { values[key(vendor, sync)] = Data(value.utf8) }
  func value(_ vendor: String, sync: Bool) -> String? { values[key(vendor, sync)].flatMap { String(data: $0, encoding: .utf8) } }
  func copyMatching(_ query: [String: Any]) -> (OSStatus, Any?) {
    guard let value = values[key(query)] else { return (errSecItemNotFound, nil) }
    return (errSecSuccess, value)
  }
  func add(_ item: [String: Any]) -> OSStatus {
    if item[kSecAttrAccount as String] as? String == rejectVendor { return errSecNotAvailable }
    guard values[key(item)] == nil else { return errSecDuplicateItem }
    values[key(item)] = item[kSecValueData as String] as? Data
    lastAccessibility = item[kSecAttrAccessible as String] as? String
    return errSecSuccess
  }
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    values[key(query)] = attributes[kSecValueData as String] as? Data
    lastAccessibility = attributes[kSecAttrAccessible as String] as? String
    return errSecSuccess
  }
  func delete(_ query: [String: Any]) -> OSStatus {
    if query[kSecAttrSynchronizable as String] as? String == kSecAttrSynchronizableAny as String {
      let vendor = query[kSecAttrAccount as String] as? String ?? ""
      values[key(vendor, false)] = nil
      values[key(vendor, true)] = nil
    } else { values[key(query)] = nil }
    return errSecSuccess
  }
}
