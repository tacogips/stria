import Foundation

extension StriaStore {
  func bindRun(_ run: AgentRunRecord, to statement: Statement) throws {
    try statement.bind(run.id, at: 1).bind(run.kind.rawValue, at: 2).bind(run.documentId, at: 3)
      .bind(run.pageNumber, at: 4).bind(run.vendor, at: 5).bind(run.model, at: 6)
      .bind(run.status.rawValue, at: 7).bind(run.error, at: 8).bind(run.imageCount, at: 9)
      .bind(StriaDateFormat.string(from: run.startedAt), at: 10).bind(StriaDateFormat.string(from: run.finishedAt), at: 11)
      .bind(run.durationMs, at: 12)
    _ = try statement.step()
  }

  func insertRun(_ run: AgentRunRecord) throws {
    let statement = try database.prepare("""
      INSERT INTO agent_runs(id,kind,document_id,page_number,vendor,model,status,error,image_count,started_at,finished_at,duration_ms)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
      """)
    try bindRun(run, to: statement)
  }

  func documentRecord(_ row: Statement) throws -> DocumentRecord {
    guard let id = row.string(0), let sha = row.string(1), let title = row.string(2),
          let filename = row.string(3), let path = row.string(4),
          let importRaw = row.string(7), let importStatus = ImportStatus(rawValue: importRaw),
          let formatRaw = row.string(9), let format = ImageFormat(rawValue: formatRaw),
          let importedRaw = row.string(15), let imported = StriaDateFormat.date(from: importedRaw),
          let updatedRaw = row.string(16), let updated = StriaDateFormat.date(from: updatedRaw) else {
      throw StriaError.database("Invalid document row")
    }
    let opened = row.string(14).flatMap(StriaDateFormat.date(from:))
    return DocumentRecord(
      id: id, sha256: sha, title: title, originalFilename: filename, originalPath: path,
      byteSize: row.int64(5), pageCount: row.int(6), importStatus: importStatus, renderDPI: row.int(8), imageFormat: format,
      ocrVendor: row.string(10), ocrModel: row.string(11), outlineJSON: row.string(12),
      lastReadPage: row.isNull(13) ? nil : row.int(13), lastOpenedAt: opened, importedAt: imported, updatedAt: updated
    )
  }

  func recordOCRStatus(_ raw: String) throws -> OCRStatus {
    guard let status = OCRStatus(rawValue: raw) else { throw StriaError.database("Invalid OCR status") }
    return status
  }

  static let documentColumns = "id,sha256,title,original_filename,original_path,byte_size,page_count,import_status," +
    "render_dpi,image_format,ocr_vendor,ocr_model,outline_json,last_read_page,last_opened_at,imported_at,updated_at"
}
