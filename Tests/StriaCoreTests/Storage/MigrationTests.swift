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
      #expect(try sqliteScalar(path: paths.database.path, sql: "PRAGMA user_version") == "3")
      for table in ["meta", "documents", "pages", "agent_runs", "chat_threads", "chat_messages"] {
        #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'") == table)
      }
    }
  }

  @Test func newerVersionIsNotModifiedAndForcedLikeSkipsFTS() async throws {
    try await withTestDataRoot { paths in
      try paths.ensureDirectories()
      try sqliteExecute(path: paths.database.path, sql: "PRAGMA user_version=4")
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

  @Test func versionOneDatabaseGainsThreadSummaryColumns() async throws {
    try await withTestDataRoot { paths in
      try paths.ensureDirectories()
      // A database left by a v1 build: schema 1 with one chat thread.
      try sqliteExecute(path: paths.database.path, sql: """
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO meta VALUES('search_backend','like');
        CREATE TABLE documents(id TEXT PRIMARY KEY, sha256 TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
          original_filename TEXT NOT NULL, original_path TEXT NOT NULL, byte_size INTEGER NOT NULL, page_count INTEGER NOT NULL,
          import_status TEXT NOT NULL, render_dpi INTEGER NOT NULL, image_format TEXT NOT NULL, ocr_vendor TEXT, ocr_model TEXT,
          outline_json TEXT, last_read_page INTEGER, last_opened_at TEXT, imported_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE chat_threads(id TEXT PRIMARY KEY, document_id TEXT, page_number INTEGER, scope TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        INSERT INTO chat_threads VALUES('old','doc',1,'page','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
        PRAGMA user_version=1;
        """)
      _ = try StriaStore(databaseURL: paths.database)
      #expect(try sqliteScalar(path: paths.database.path, sql: "PRAGMA user_version") == "3")
      #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT COUNT(*) FROM pragma_table_info('chat_threads') WHERE name='title'") == "1")
      #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT scope FROM chat_threads WHERE id='old'") == "page")
      #expect(try sqliteScalar(path: paths.database.path, sql: "SELECT COUNT(*) FROM pragma_table_info('chat_threads') WHERE name IN ('summary','summary_through_message_id','summary_updated_at')") == "3")
      _ = try StriaStore(databaseURL: paths.database)
      #expect(try sqliteScalar(path: paths.database.path, sql: "PRAGMA user_version") == "3")
    }
  }
}
