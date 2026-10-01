import CryptoKit
import Foundation
import StriaCore
import Testing

@Suite("MigrationTests") struct MigrationTests {
  @Test func freshDatabaseMigratesAndReopens() async throws {
    try await withTestDataRoot { paths in
      let first = try openStorage(paths: paths)
      let backend = await first.searchBackend
      #expect(backend == .fts5 || backend == .like)
      let reopened = try openStorage(paths: paths)
      #expect(await reopened.searchBackend == backend)
      #expect(try sqliteScalar(path: paths.database.path, sql: "PRAGMA user_version") == "1")
      for table in ["meta", "documents", "pages", "agent_runs", "chat_threads", "chat_messages"] {
        #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'") == table)
      }
    }
  }

  @Test func newerVersionIsNotModifiedAndForcedLikeSkipsFTS() async throws {
    try await withTestDataRoot { paths in
      try paths.ensureDirectories()
      try sqliteExecute(path: paths.database.path, sql: "PRAGMA user_version=2")
      let before = SHA256.hash(data: try Data(contentsOf: paths.database)).map { String(format: "%02x", $0) }.joined()
      do {
        _ = try StriaStore(databaseURL: paths.database)
        Issue.record("Expected databaseTooNew")
      } catch let error as StriaError { #expect(error.code == .databaseTooNew) }
      let after = SHA256.hash(data: try Data(contentsOf: paths.database)).map { String(format: "%02x", $0) }.joined()
      #expect(before == after)
    }
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: true)
      #expect(await store.searchBackend == .like)
      #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT name FROM sqlite_master WHERE name='page_fts'") == nil)
    }
  }
}
