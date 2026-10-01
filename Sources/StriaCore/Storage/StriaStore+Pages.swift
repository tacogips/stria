import Foundation

extension StriaStore {
  public func insertPage(documentId: String, pageNumber: Int, image: StoredPageImage) throws {
    try database.transaction {
      let statement = try database.prepare("""
        INSERT INTO pages(document_id,page_number,image,image_format,width,height,ocr_status,created_at)
        VALUES(?,?,?,?,?,?,'pending',?)
        """)
      try statement.bind(documentId, at: 1).bind(pageNumber, at: 2).bind(image.data, at: 3)
        .bind(image.format.rawValue, at: 4).bind(image.width, at: 5).bind(image.height, at: 6).bind(nowString(), at: 7)
      _ = try statement.step()
    }
  }

  public func pageNumbers(documentId: String) throws -> [Int] {
    let statement = try database.prepare("SELECT page_number FROM pages WHERE document_id=? ORDER BY page_number")
    try statement.bind(documentId, at: 1)
    var numbers: [Int] = []
    while try statement.step() { numbers.append(statement.int(0)) }
    return numbers
  }

  public func pageInfo(documentId: String, page: Int) throws -> PageInfo? {
    let statement = try database.prepare("""
      SELECT document_id,page_number,image_format,width,height,ocr_status,ocr_text,ocr_vendor,ocr_model,ocr_error,ocr_attempts,ocr_updated_at
      FROM pages WHERE document_id=? AND page_number=?
      """)
    try statement.bind(documentId, at: 1).bind(page, at: 2)
    guard try statement.step() else { return nil }
    return try pageInfoRecord(statement)
  }

  public func pageInfos(documentId: String) throws -> [PageInfo] {
    let statement = try database.prepare("""
      SELECT document_id,page_number,image_format,width,height,ocr_status,ocr_text,ocr_vendor,ocr_model,ocr_error,ocr_attempts,ocr_updated_at
      FROM pages WHERE document_id=? ORDER BY page_number
      """)
    try statement.bind(documentId, at: 1)
    var pages: [PageInfo] = []
    while try statement.step() { pages.append(try pageInfoRecord(statement)) }
    return pages
  }

  public func pageImage(documentId: String, page: Int) throws -> StoredPageImage? {
    let statement = try database.prepare("SELECT image,image_format,width,height FROM pages WHERE document_id=? AND page_number=?")
    try statement.bind(documentId, at: 1).bind(page, at: 2)
    guard try statement.step(), let data = statement.data(0), let rawFormat = statement.string(1),
          let format = ImageFormat(rawValue: rawFormat) else { return nil }
    return StoredPageImage(data: data, format: format, width: statement.int(2), height: statement.int(3))
  }

  public func pageNumbers(documentId: String, statuses: Set<OCRStatus>) throws -> [Int] {
    guard !statuses.isEmpty else { return [] }
    let values = statuses.map { "'\($0.rawValue)'" }.sorted().joined(separator: ",")
    let statement = try database.prepare("SELECT page_number FROM pages WHERE document_id=? AND ocr_status IN (\(values)) ORDER BY page_number")
    try statement.bind(documentId, at: 1)
    var numbers: [Int] = []
    while try statement.step() { numbers.append(statement.int(0)) }
    return numbers
  }

  public func recordOCRSuccess(
    documentId: String, page: Int, text: String, vendor: String, model: String?, run: AgentRunRecord
  ) throws {
    try database.transaction {
      try insertRun(run)
      let normalized = text.precomposedStringWithCompatibilityMapping
      let update = try database.prepare("""
        UPDATE pages SET ocr_status='done',ocr_text=?,search_text=?,ocr_vendor=?,ocr_model=?,ocr_error=NULL,
          ocr_updated_at=? WHERE document_id=? AND page_number=?
        """)
      try update.bind(text, at: 1).bind(normalized, at: 2).bind(vendor, at: 3).bind(model, at: 4)
        .bind(nowString(), at: 5).bind(documentId, at: 6).bind(page, at: 7)
      _ = try update.step()
      guard database.changes > 0 else { throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)") }
      if searchBackend == .fts5 { try replaceFTS(documentId: documentId, page: page, text: normalized) }
    }
  }

  public func recordOCRFailure(
    documentId: String, page: Int, error: String, vendor: String, model: String?, run: AgentRunRecord
  ) throws {
    try database.transaction {
      try insertRun(run)
      let update = try database.prepare("""
        UPDATE pages SET ocr_status='failed',ocr_error=?,ocr_attempts=ocr_attempts+1,ocr_text=NULL,search_text=NULL,
          ocr_vendor=?,ocr_model=?,ocr_updated_at=? WHERE document_id=? AND page_number=?
        """)
      try update.bind(error, at: 1).bind(vendor, at: 2).bind(model, at: 3).bind(nowString(), at: 4)
        .bind(documentId, at: 5).bind(page, at: 6)
      _ = try update.step()
      guard database.changes > 0 else { throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)") }
      if searchBackend == .fts5 { try deleteFTS(documentId: documentId, page: page) }
    }
  }

  private func pageInfoRecord(_ row: Statement) throws -> PageInfo {
    guard let docId = row.string(0), let rawFormat = row.string(2), let format = ImageFormat(rawValue: rawFormat),
          let rawStatus = row.string(5), let status = OCRStatus(rawValue: rawStatus) else {
      throw StriaError.database("Invalid page row")
    }
    return PageInfo(documentId: docId, pageNumber: row.int(1), imageFormat: format, width: row.int(3), height: row.int(4),
                    ocrStatus: status, ocrText: row.string(6), ocrVendor: row.string(7), ocrModel: row.string(8),
                    ocrError: row.string(9), ocrAttempts: row.int(10), ocrUpdatedAt: row.string(11).flatMap(StriaDateFormat.date(from:)))
  }

  private func replaceFTS(documentId: String, page: Int, text: String) throws {
    try deleteFTS(documentId: documentId, page: page)
    let insert = try database.prepare("INSERT INTO page_fts(document_id,page_number,body) VALUES(?,?,?)")
    try insert.bind(documentId, at: 1).bind(String(page), at: 2).bind(text, at: 3)
    _ = try insert.step()
  }

  private func deleteFTS(documentId: String, page: Int) throws {
    let delete = try database.prepare("DELETE FROM page_fts WHERE document_id=? AND page_number=?")
    try delete.bind(documentId, at: 1).bind(String(page), at: 2)
    _ = try delete.step()
  }
}
