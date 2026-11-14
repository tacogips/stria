import Foundation

public enum ConfigStore {
  public static func loadOrCreate(paths: StriaPaths) throws -> StriaConfig {
    let manager = FileManager.default
    guard manager.fileExists(atPath: paths.config.path) else {
      let config = StriaConfig.defaults
      try paths.ensureDirectories()
      try save(config, paths: paths)
      return config
    }
    do {
      let data = try Data(contentsOf: paths.config)
      let config = try JSONDecoder().decode(StriaConfig.self, from: data)
      try config.validate()
      return config
    } catch let error as StriaError {
      throw error
    } catch {
      throw StriaError.config("Invalid config JSON: \(error.localizedDescription)")
    }
  }

  public static func save(_ config: StriaConfig, paths: StriaPaths) throws {
    try config.validate()
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try paths.ensureDirectories()
      try encoder.encode(config).write(to: paths.config, options: .atomic)
    } catch let error as StriaError {
      throw error
    } catch {
      throw StriaError.io("Could not write config: \(error.localizedDescription)")
    }
  }
}
