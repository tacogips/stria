import Foundation
import Security

/// Secret values live outside config.json. Implementations must be safe across service tasks.
public protocol CredentialStore: Sendable {
  func read(vendor: String) throws -> String?
  func write(_ value: String, vendor: String) throws
  func delete(vendor: String) throws
}

/// Generic passwords scoped to this app and the vendor id.
public struct KeychainCredentialStore: CredentialStore {
  public static let service = "me.tacogips.stria.apikey"
  public init() {}

  public func read(vendor: String) throws -> String? {
    var query = query(vendor: vendor)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
      throw ServiceError.unavailable("Could not decode the saved API key")
    }
    return value
  }

  public func write(_ value: String, vendor: String) throws {
    if value.isEmpty { try delete(vendor: vendor); return }
    let query = query(vendor: vendor)
    let data = Data(value.utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData] = data
      item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      try check(SecItemAdd(item as CFDictionary, nil))
    } else {
      try check(status)
    }
  }

  public func delete(vendor: String) throws {
    let status = SecItemDelete(query(vendor: vendor) as CFDictionary)
    if status != errSecItemNotFound { try check(status) }
  }

  private func query(vendor: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: vendor]
  }

  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else {
      throw ServiceError.unavailable("Keychain operation failed (status \(status))")
    }
  }
}

/// Builds a fresh service environment using the variable names from current settings.
public struct CredentialEnvironment: Sendable {
  public let platform: StriaPlatform
  public let store: any CredentialStore
  private let processEnvironment: [String: String]

  public init(environment: [String: String], platform: StriaPlatform = .current,
              store: any CredentialStore = KeychainCredentialStore()) {
    processEnvironment = environment
    self.platform = platform
    self.store = store
  }

  public func merged(credentials: [String: String]) throws -> [String: String] {
    var result = processEnvironment
    guard platform == .iOS else { return result }
    for vendor in credentials.keys.sorted() where KnownVendors.apiKeyVendors.contains(vendor) {
      guard let name = credentials[vendor], !name.isEmpty,
            let value = try store.read(vendor: vendor), !value.isEmpty else { continue }
      result[name] = value
    }
    return result
  }

  func merged(settings: ServiceSettings) throws -> [String: String] {
    try merged(credentials: settings.apiKeyEnvironment.map { [settings.vendor: $0] } ?? [:])
  }
}
