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

  /// Validates and writes the configuration, then makes it current for every
  /// later call in this process.
  public func saveConfig(_ config: StriaConfig) throws {
    try ConfigStore.save(config, paths: paths)
    environment.updateConfig(config)
  }
}
