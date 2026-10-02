import Foundation

extension StriaStore {
  public func insertDocument(_ record: DocumentRecord) throws {
    let statement = try database.prepare("""
      INSERT INTO documents(id,sha256,title,original_filename,original_path,byte_size,page_count,import_status,render_dpi,image_format,
        ocr_vendor,ocr_model,outline_json,last_read_page,last_opened_at,imported_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      """)
    try statement.bind(record.id, at: 1).bind(record.sha256, at: 2).bind(record.title, at: 3)
      .bind(record.originalFilename, at: 4).bind(record.originalPath, at: 5).bind(record.byteSize, at: 6)
      .bind(record.pageCount, at: 7).bind(record.importStatus.rawValue, at: 8).bind(record.renderDPI, at: 9)
      .bind(record.imageFormat.rawValue, at: 10).bind(record.ocrVendor, at: 11).bind(record.ocrModel, at: 12)
      .bind(record.outlineJSON, at: 13).bind(record.lastReadPage, at: 14)
      .bind(record.lastOpenedAt.map(StriaDateFormat.string(from:)), at: 15)
      .bind(StriaDateFormat.string(from: record.importedAt), at: 16).bind(StriaDateFormat.string(from: record.updatedAt), at: 17)
    _ = try statement.step()
  }

  public func document(id: String) throws -> DocumentRecord? {
    let statement = try database.prepare("SELECT \(Self.documentColumns) FROM documents WHERE id=?")
    try statement.bind(id, at: 1)
    guard try statement.step() else { return nil }
    return try documentRecord(statement)
  }

  public func document(sha256: String) throws -> DocumentRecord? {
    let statement = try database.prepare("SELECT \(Self.documentColumns) FROM documents WHERE sha256=?")
    try statement.bind(sha256, at: 1)
    guard try statement.step() else { return nil }
    return try documentRecord(statement)
  }

  public func markDocumentReady(id: String, outlineJSON: String?) throws {
    let statement = try database.prepare("UPDATE documents SET import_status='ready',outline_json=?,updated_at=? WHERE id=?")
    try statement.bind(outlineJSON, at: 1).bind(nowString(), at: 2).bind(id, at: 3)
    _ = try statement.step()
    guard database.changes > 0 else { throw StriaError.documentNotFound("Document not found: \(id)") }
  }

  public func listDocuments(order: DocumentOrder) throws -> [DocumentRecord] {
    let ordering = order == .importedDescending
      ? "imported_at DESC,id"
      : "last_opened_at IS NULL,last_opened_at DESC,imported_at DESC"
    let statement = try database.prepare("SELECT \(Self.documentColumns) FROM documents ORDER BY \(ordering)")
    var documents: [DocumentRecord] = []
    while try statement.step() { documents.append(try documentRecord(statement)) }
    return documents
  }

  public func ocrCounts(documentId: String) throws -> OCRCounts {
    let statement = try database.prepare("""
      SELECT SUM(ocr_status='done'),SUM(ocr_status='failed'),SUM(ocr_status='pending')
      FROM pages WHERE document_id=?
      """)
    try statement.bind(documentId, at: 1)
    _ = try statement.step()
    return OCRCounts(done: statement.int(0), failed: statement.int(1), pending: statement.int(2))
  }

  public func setLastReadPage(documentId: String, page: Int) throws {
    let statement = try database.prepare("UPDATE documents SET last_read_page=?,updated_at=? WHERE id=?")
    try statement.bind(page, at: 1).bind(nowString(), at: 2).bind(documentId, at: 3)
    _ = try statement.step()
    guard database.changes > 0 else { throw StriaError.documentNotFound("Document not found: \(documentId)") }
  }

  /// Deletes the document row. Pages, chat threads and messages cascade;
  /// agent runs keep their rows with `document_id` set to null.
  public func deleteDocument(id: String) throws -> Bool {
    try database.transaction {
      if searchBackend == .fts5 {
        let fts = try database.prepare("DELETE FROM page_fts WHERE document_id=?")
        try fts.bind(id, at: 1)
        _ = try fts.step()
      }
      let statement = try database.prepare("DELETE FROM documents WHERE id=?")
      try statement.bind(id, at: 1)
      _ = try statement.step()
      return database.changes > 0
    }
  }

  public func markOpened(documentId: String) throws {
    let statement = try database.prepare("UPDATE documents SET last_opened_at=?,updated_at=? WHERE id=?")
    let now = nowString()
    try statement.bind(now, at: 1).bind(now, at: 2).bind(documentId, at: 3)
    _ = try statement.step()
    guard database.changes > 0 else { throw StriaError.documentNotFound("Document not found: \(documentId)") }
  }
}
