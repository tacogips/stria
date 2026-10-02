import Foundation

public struct StriaLibrary: Sendable {
  public let environment: StriaEnvironment
  public let store: StriaStore
  public var paths: StriaPaths { environment.paths }

  public static func open(environment: StriaEnvironment, storeOptions: StoreOptions = .init()) throws -> StriaLibrary {
    try environment.paths.ensureDirectories()
    let store = try StriaStore(databaseURL: environment.paths.database, options: storeOptions, clock: environment.clock)
    return StriaLibrary(environment: environment, store: store)
  }

  private init(environment: StriaEnvironment, store: StriaStore) {
    self.environment = environment
    self.store = store
  }

  /// The vendor and model the user last chose in the chat, kept in SQLite so
  /// the next session starts with them.
  public func lastAgentSelection() async throws -> AgentSelection? {
    guard let vendor = try await store.meta(AgentSelection.vendorKey), !vendor.isEmpty else { return nil }
    return AgentSelection(vendor: vendor, model: try await store.meta(AgentSelection.modelKey))
  }

  public func setLastAgentSelection(_ selection: AgentSelection?) async throws {
    try await store.setMeta(AgentSelection.vendorKey, selection?.vendor)
    try await store.setMeta(AgentSelection.modelKey, selection?.model)
  }

  /// Validates and writes the configuration, then makes it current for every
  /// later call in this process.
  public func saveConfig(_ config: StriaConfig) throws {
    try ConfigStore.save(config, paths: paths)
    environment.updateConfig(config)
  }
}
