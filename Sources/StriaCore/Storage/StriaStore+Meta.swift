import Foundation

extension StriaStore {
  public func meta(_ key: String) throws -> String? {
    let statement = try database.prepare("SELECT value FROM meta WHERE key=?")
    try statement.bind(key, at: 1)
    guard try statement.step() else { return nil }
    return statement.string(0)
  }

  public func setMeta(_ key: String, _ value: String?) throws {
    if let value {
      let statement = try database.prepare("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
      try statement.bind(key, at: 1).bind(value, at: 2)
      _ = try statement.step()
    } else {
      let statement = try database.prepare("DELETE FROM meta WHERE key=?")
      try statement.bind(key, at: 1)
      _ = try statement.step()
    }
  }
}
