import Foundation

struct MigrationResult {
  let backend: SearchBackend
}

enum Migrations {
  static let version = 3

  static func run(_ database: SQLiteConnection, forceLikeSearch: Bool) throws -> MigrationResult {
    // busy_timeout comes first: even reading user_version can hit the lock of
    // another process (the CLI mid-import while the app opens the store).
    try database.execute("PRAGMA busy_timeout=5000")
    try database.execute("PRAGMA foreign_keys=ON")
    let version = try userVersion(database)
    guard version <= Self.version else {
      throw StriaError.databaseTooNew("Database schema version \(version) is newer than supported version \(self.version)")
    }
    // Only now touch the file: a too-new database must stay byte-identical.
    let journal = try database.prepare("PRAGMA journal_mode=WAL")
    _ = try journal.step()
    _ = try journal.step()
    // NORMAL is durable against application crashes in WAL mode and avoids
    // one fsync per page insert during import.
    try database.execute("PRAGMA synchronous=NORMAL")
    if version == 0 {
      try database.transaction {
        let current = try userVersion(database)
        guard current <= self.version else {
          throw StriaError.databaseTooNew("Database schema version \(current) is newer than supported version \(self.version)")
        }
        guard current == 0 else { return }
        try createSchema(database)
        let backend = try probeSearchBackend(database, forceLikeSearch: forceLikeSearch)
        let meta = try database.prepare("INSERT INTO meta(key, value) VALUES ('search_backend', ?)")
        try meta.bind(backend.rawValue, at: 1)
        _ = try meta.step()
        try database.execute("PRAGMA user_version=1")
      }
    }
    if try userVersion(database) < 2 {
      try database.transaction {
        // Re-check inside the write lock: another process may have upgraded.
        guard try userVersion(database) < 2 else { return }
        try addThreadSummaryColumns(database)
        try database.execute("PRAGMA user_version=2")
      }
    }
    if try userVersion(database) < 3 {
      try database.transaction {
        guard try userVersion(database) < 3 else { return }
        try addThreadTitleColumn(database)
        try database.execute("PRAGMA user_version=3")
      }
    }
    return MigrationResult(backend: try storedBackend(database))
  }

  private static func userVersion(_ database: SQLiteConnection) throws -> Int {
    let statement = try database.prepare("PRAGMA user_version")
    guard try statement.step() else { throw database.databaseError() }
    return statement.int(0)
  }

  /// Migration 2: a stored summary per chat thread, and the newest message it
  /// covers (a newer message makes the summary stale).
  static func addThreadSummaryColumns(_ db: SQLiteConnection) throws {
    try db.execute("""
      ALTER TABLE chat_threads ADD COLUMN summary TEXT;
      ALTER TABLE chat_threads ADD COLUMN summary_through_message_id INTEGER;
      ALTER TABLE chat_threads ADD COLUMN summary_updated_at TEXT;
      """)
  }

  /// Migration 3: a short title per chat thread, shown in the agent pane
  /// header and the history list.
  static func addThreadTitleColumn(_ db: SQLiteConnection) throws {
    try db.execute("ALTER TABLE chat_threads ADD COLUMN title TEXT;")
  }

  /// Schema version 1, kept as the first step of every fresh database.
  static func createSchema(_ db: SQLiteConnection) throws {
    try db.execute("""
      CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE documents(
        id TEXT PRIMARY KEY, sha256 TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
        original_filename TEXT NOT NULL, original_path TEXT NOT NULL,
        byte_size INTEGER NOT NULL, page_count INTEGER NOT NULL,
        import_status TEXT NOT NULL CHECK(import_status IN ('rendering','ready')),
        render_dpi INTEGER NOT NULL, image_format TEXT NOT NULL,
        ocr_vendor TEXT, ocr_model TEXT, outline_json TEXT, last_read_page INTEGER,
        last_opened_at TEXT, imported_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      CREATE TABLE pages(
        document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER NOT NULL CHECK(page_number >= 1), image BLOB NOT NULL,
        image_format TEXT NOT NULL CHECK(image_format IN ('heic','jpeg')),
        width INTEGER NOT NULL, height INTEGER NOT NULL,
        ocr_status TEXT NOT NULL DEFAULT 'pending' CHECK(ocr_status IN ('pending','done','failed')),
        ocr_text TEXT, search_text TEXT, ocr_vendor TEXT, ocr_model TEXT, ocr_error TEXT,
        ocr_attempts INTEGER NOT NULL DEFAULT 0, ocr_updated_at TEXT, created_at TEXT NOT NULL,
        PRIMARY KEY(document_id, page_number));
      CREATE TABLE agent_runs(
        id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('ocr','ask')),
        document_id TEXT REFERENCES documents(id) ON DELETE SET NULL, page_number INTEGER,
        vendor TEXT NOT NULL, model TEXT, status TEXT NOT NULL CHECK(status IN ('ok','failed')),
        error TEXT, image_count INTEGER NOT NULL, started_at TEXT NOT NULL,
        finished_at TEXT NOT NULL, duration_ms INTEGER NOT NULL);
      CREATE TABLE chat_threads(
        id TEXT PRIMARY KEY, document_id TEXT REFERENCES documents(id) ON DELETE CASCADE,
        page_number INTEGER, scope TEXT NOT NULL CHECK(scope IN ('page','nearby','document','library')),
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      CREATE TABLE chat_messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
        role TEXT NOT NULL CHECK(role IN ('user','assistant')),
        status TEXT NOT NULL DEFAULT 'ok' CHECK(status IN ('ok','error')), content TEXT NOT NULL,
        document_id TEXT, page_number INTEGER, vendor TEXT, model TEXT,
        agent_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL, citations_json TEXT, created_at TEXT NOT NULL);
      CREATE INDEX chat_messages_doc_page ON chat_messages(document_id, page_number, created_at);
      CREATE INDEX chat_messages_thread ON chat_messages(thread_id, id);
      CREATE INDEX pages_ocr_status ON pages(document_id, ocr_status);
      CREATE INDEX agent_runs_doc ON agent_runs(document_id, started_at);
      """)
  }

  private static func probeSearchBackend(_ db: SQLiteConnection, forceLikeSearch: Bool) throws -> SearchBackend {
    guard !forceLikeSearch else { return .like }
    do {
      try db.savepoint("fts_probe") {
        try db.execute("CREATE VIRTUAL TABLE page_fts USING fts5(document_id UNINDEXED, page_number UNINDEXED, body, tokenize='trigram')")
      }
      return .fts5
    } catch {
      return .like
    }
  }

  private static func storedBackend(_ db: SQLiteConnection) throws -> SearchBackend {
    let statement = try db.prepare("SELECT value FROM meta WHERE key='search_backend'")
    guard try statement.step(), let raw = statement.string(0), let backend = SearchBackend(rawValue: raw) else {
      throw StriaError.database("Missing or invalid search_backend metadata")
    }
    return backend
  }
}
