import Foundation
import SQLite3
import StriaCore

func storageDocument(_ id: String, imported: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> DocumentRecord {
  DocumentRecord(id: id, sha256: "sha-\(id)", title: "Title \(id)", originalFilename: "\(id).pdf",
                 originalPath: "originals/\(id).pdf", byteSize: 42, pageCount: 3, importStatus: .rendering,
                 renderDPI: 150, imageFormat: .heic, importedAt: imported, updatedAt: imported)
}

func storageImage(_ bytes: [UInt8] = [1, 2, 3]) -> StoredPageImage {
  StoredPageImage(data: Data(bytes), format: .heic, width: 10, height: 10)
}

func storageRun(_ id: String = UUID().uuidString, documentId: String? = "doc", page: Int? = 1,
                kind: RunKind = .ocr, status: RunStatus = .ok, date: Date = Date(timeIntervalSince1970: 1_800_000_010)) -> AgentRunRecord {
  AgentRunRecord(id: id, kind: kind, documentId: documentId, pageNumber: page, vendor: "test", model: "m",
                 status: status, error: status == .failed ? "redacted" : nil, imageCount: 1,
                 startedAt: date, finishedAt: date.addingTimeInterval(1), durationMs: 1)
}

func openStorage(paths: StriaPaths, like: Bool = false) throws -> StriaStore {
  try paths.ensureDirectories()
  return try StriaStore(databaseURL: paths.database, options: StoreOptions(forceLikeSearch: like))
}

func sqliteScalar(path: String, sql: String) throws -> String? {
  var database: OpaquePointer?
  guard sqlite3_open(path, &database) == SQLITE_OK, let database else { throw StriaError.database("Could not open test database") }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StriaError.database("Could not prepare test query") }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
  return String(cString: value)
}

func sqliteExecute(path: String, sql: String) throws {
  var database: OpaquePointer?
  guard sqlite3_open(path, &database) == SQLITE_OK, let database else { throw StriaError.database("Could not open test database") }
  defer { sqlite3_close(database) }
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StriaError.database(String(cString: sqlite3_errmsg(database))) }
}
