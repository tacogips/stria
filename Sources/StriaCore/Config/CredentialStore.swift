import Foundation
import Security

/// Secret values live outside config.json. Implementations must be safe across service tasks.
public protocol CredentialStore: Sendable {
  func read(vendor: String) throws -> String?
  func write(_ value: String, vendor: String) throws
  func delete(vendor: String) throws
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
    for vendor in credentials.keys.sorted() where KnownVendors.apiKeyVendors.contains(vendor) {
      guard let name = credentials[vendor], !name.isEmpty,
            let value = try store.read(vendor: vendor), !value.isEmpty else { continue }
      if platform == .macOS, let existing = result[name], !existing.isEmpty { continue }
      result[name] = value
    }
    return result
  }

  func merged(settings: ServiceSettings) throws -> [String: String] {
    try merged(credentials: settings.apiKeyEnvironment.map { [settings.vendor: $0] } ?? [:])
  }
}
