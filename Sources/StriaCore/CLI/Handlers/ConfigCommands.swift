import Foundation

enum ConfigCommands {
  static func run(_ command: CLICommand, config: inout StriaConfig, paths: StriaPaths) throws -> any Encodable {
    switch command {
    case .configGet(let key):
      guard let key else { return config }
      return ConfigValueOutput(key: key, value: try ConfigKeyPath.value(of: key, in: config))
    case .configSet(let key, let raw):
      let updated = try ConfigKeyPath.setting(key, to: raw, in: config)
      try ConfigStore.save(updated, paths: paths)
      config = updated
      return ConfigValueOutput(key: key, value: try ConfigKeyPath.value(of: key, in: config))
    case .paths:
      return PathsOutput(home: paths.root.path, database: paths.database.path, originals: paths.originals.path,
                         cache: paths.cache.path, config: paths.config.path, logs: paths.logs.path)
    default:
      throw StriaError.usage("Not a config command")
    }
  }
}
