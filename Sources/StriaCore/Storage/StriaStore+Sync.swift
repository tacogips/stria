import Foundation

extension StriaStore {
  func applySyncDocument(_ record: SyncDocument) throws {
    let outline = try record.outline.flatMap { String(data: try JSONEncoder().encode($0), encoding: .utf8) }
    let update = try database.prepare("""
      UPDATE documents SET title=?,original_filename=?,byte_size=?,outline_json=?,imported_at=?,updated_at=? WHERE id=?
      """)
    try update.bind(record.title, at: 1).bind(record.originalFilename, at: 2).bind(record.byteSize, at: 3)
      .bind(outline, at: 4).bind(StriaDateFormat.string(from: record.importedAt), at: 5)
      .bind(StriaDateFormat.string(from: record.updatedAt), at: 6).bind(record.docId, at: 7)
    _ = try update.step()
  }

  func applySyncOCR(documentId: String, record: SyncOCR) throws {
    guard record.status != .pending else { throw StriaError.io("Pending OCR cannot be synced") }
    try database.transaction {
      let text = record.status == .done ? record.text : nil
      let normalized = text.map { SearchQueryBuilder.normalize($0) }
      let tags = String(data: try JSONEncoder().encode(record.tags), encoding: .utf8)
      let update = try database.prepare("""
        UPDATE pages SET ocr_status=?,ocr_text=?,search_text=?,ocr_tags_json=?,ocr_error=?,ocr_vendor=?,ocr_model=?,ocr_updated_at=?
        WHERE document_id=? AND page_number=?
        """)
      try update.bind(record.status.rawValue, at: 1).bind(text, at: 2).bind(normalized, at: 3).bind(tags, at: 4)
        .bind(record.error, at: 5).bind(record.vendor, at: 6).bind(record.model, at: 7)
        .bind(StriaDateFormat.string(from: record.updatedAt), at: 8).bind(documentId, at: 9).bind(record.page, at: 10)
      _ = try update.step()
      guard database.changes > 0 else { throw StriaError.pageNotFound("Page \(record.page) not found in document \(documentId)") }
      if searchBackend == .fts5 {
        try deleteFTS(documentId: documentId, page: record.page)
        if let normalized { try replaceFTS(documentId: documentId, page: record.page, text: normalized) }
      }
    }
  }

  func syncSummaries(documentId: String) throws -> [SyncSummary] {
    try pageSummaries(documentId: documentId).map { record in
      let row = try database.prepare("SELECT source_ocr_updated_at FROM page_summaries WHERE document_id=? AND page_number=?")
      try row.bind(documentId, at: 1).bind(record.pageNumber, at: 2)
      _ = try row.step()
      return SyncSummary(record: record, sourceOCRUpdatedAt: row.string(0).flatMap(StriaDateFormat.date(from:)))
    }
  }

  func applySyncSummary(_ value: SyncSummary) throws {
    let record = value.record
    guard try pageInfo(documentId: record.documentId, page: record.pageNumber) != nil else {
      throw StriaError.pageNotFound("Summary page not found")
    }
    let update = try database.prepare("""
      INSERT INTO page_summaries(document_id,page_number,status,summary,error,language,instruction,vendor,model,source_ocr_updated_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(document_id,page_number) DO UPDATE SET
      status=excluded.status,summary=excluded.summary,error=excluded.error,language=excluded.language,instruction=excluded.instruction,
      vendor=excluded.vendor,model=excluded.model,source_ocr_updated_at=excluded.source_ocr_updated_at,updated_at=excluded.updated_at
      """)
    try update.bind(record.documentId, at: 1).bind(record.pageNumber, at: 2).bind(record.status.rawValue, at: 3)
      .bind(record.summary, at: 4).bind(record.error, at: 5).bind(record.language, at: 6).bind(record.instruction, at: 7)
      .bind(record.vendor, at: 8).bind(record.model, at: 9).bind(value.sourceOCRUpdatedAt.map(StriaDateFormat.string(from:)), at: 10)
      .bind(StriaDateFormat.string(from: record.updatedAt), at: 11)
    _ = try update.step()
  }

  func pendingSyncDeletions() throws -> [String: Date] {
    let rows = try database.prepare("SELECT key,value FROM meta WHERE key LIKE 'sync.deleted.%'")
    var values: [String: Date] = [:]
    while try rows.step() {
      if let key = rows.string(0), let date = rows.string(1).flatMap(StriaDateFormat.date(from:)) {
        values[String(key.dropFirst("sync.deleted.".count))] = date
      }
    }
    return values
  }

  /// The intent and deletion commit together, before filesystem cleanup.
  func deleteDocumentForSync(id: String, deletedAt: Date) throws -> Bool {
    try database.transaction {
      guard try document(id: id) != nil else { return false }
      try setMeta("sync.deleted." + id, StriaDateFormat.string(from: deletedAt))
      return try deleteDocument(id: id)
    }
  }
}
