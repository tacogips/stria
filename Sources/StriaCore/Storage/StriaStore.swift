import Foundation

public struct StoreOptions: Sendable {
  public var forceLikeSearch: Bool
  public init(forceLikeSearch: Bool = false) { self.forceLikeSearch = forceLikeSearch }
}

public actor StriaStore {
  let database: SQLiteConnection
  let clock: @Sendable () -> Date
  public let searchBackend: SearchBackend

  public init(
    databaseURL: URL,
    options: StoreOptions = .init(),
    clock: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    let connection = try SQLiteConnection(path: databaseURL.path)
    let migration = try Migrations.run(connection, forceLikeSearch: options.forceLikeSearch)
    database = connection
    searchBackend = migration.backend
    self.clock = clock
  }

  func nowString() -> String { StriaDateFormat.string(from: clock()) }
}
