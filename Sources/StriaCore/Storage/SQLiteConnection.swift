import Foundation
import SQLite3

final class SQLiteConnection {
  private var handle: OpaquePointer?

  init(path: String) throws {
    let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database"
      sqlite3_close_v2(handle)
      throw StriaError.database(message)
    }
  }

  deinit { sqlite3_close_v2(handle) }

  func execute(_ sql: String) throws {
    guard let handle else { throw StriaError.database("Database is closed") }
    var message: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(handle, sql, nil, nil, &message)
    guard result == SQLITE_OK else {
      let detail = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
      sqlite3_free(message)
      throw StriaError.database(detail)
    }
  }

  func prepare(_ sql: String) throws -> Statement {
    guard let handle else { throw StriaError.database("Database is closed") }
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else { throw databaseError() }
    return Statement(connection: self, handle: statement)
  }

  func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let value = try body()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func savepoint<T>(_ name: String, _ body: () throws -> T) throws -> T {
    try execute("SAVEPOINT \(name)")
    do {
      let value = try body()
      try execute("RELEASE SAVEPOINT \(name)")
      return value
    } catch {
      try? execute("ROLLBACK TO SAVEPOINT \(name)")
      try? execute("RELEASE SAVEPOINT \(name)")
      throw error
    }
  }

  var lastInsertRowID: Int64 { handle.map(sqlite3_last_insert_rowid) ?? 0 }
  var changes: Int { handle.map { Int(sqlite3_changes($0)) } ?? 0 }

  func databaseError() -> StriaError {
    StriaError.database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite operation failed")
  }
}

final class Statement {
  private let connection: SQLiteConnection
  private var handle: OpaquePointer?
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  fileprivate init(connection: SQLiteConnection, handle: OpaquePointer) {
    self.connection = connection
    self.handle = handle
  }

  deinit { sqlite3_finalize(handle) }

  @discardableResult func bind(_ value: Int, at index: Int32) throws -> Self { try bind(Int64(value), at: index) }
  @discardableResult func bind(_ value: Int?, at index: Int32) throws -> Self {
    guard let value else { return try bindNull(at: index) }
    return try bind(value, at: index)
  }
  @discardableResult func bind(_ value: Int64, at index: Int32) throws -> Self { try check(sqlite3_bind_int64(handle, index, value)) }
  @discardableResult func bind(_ value: Double, at index: Int32) throws -> Self { try check(sqlite3_bind_double(handle, index, value)) }

  @discardableResult func bind(_ value: String?, at index: Int32) throws -> Self {
    guard let value else { return try bindNull(at: index) }
    return try check(sqlite3_bind_text(handle, index, value, -1, transient))
  }

  @discardableResult func bind(_ value: Data?, at index: Int32) throws -> Self {
    guard let value else { return try bindNull(at: index) }
    guard !value.isEmpty else { return try check(sqlite3_bind_zeroblob(handle, index, 0)) }
    return try value.withUnsafeBytes { bytes in
      try check(sqlite3_bind_blob(handle, index, bytes.baseAddress, Int32(value.count), transient))
    }
  }

  @discardableResult func bindNull(at index: Int32) throws -> Self { try check(sqlite3_bind_null(handle, index)) }

  func step() throws -> Bool {
    let result = sqlite3_step(handle)
    if result == SQLITE_ROW { return true }
    if result == SQLITE_DONE { return false }
    throw connection.databaseError()
  }

  func int(_ column: Int32) -> Int { Int(sqlite3_column_int(handle, column)) }
  func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
  func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
  func string(_ column: Int32) -> String? {
    guard let value = sqlite3_column_text(handle, column) else { return nil }
    return String(cString: value)
  }
  func data(_ column: Int32) -> Data? {
    guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
    let count = Int(sqlite3_column_bytes(handle, column))
    guard count > 0, let pointer = sqlite3_column_blob(handle, column) else { return Data() }
    return Data(bytes: pointer, count: count)
  }
  func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }

  func reset() throws {
    let result = sqlite3_reset(handle)
    guard result == SQLITE_OK else { throw connection.databaseError() }
    sqlite3_clear_bindings(handle)
  }

  @discardableResult private func check(_ result: Int32) throws -> Self {
    guard result == SQLITE_OK else { throw connection.databaseError() }
    return self
  }
}
