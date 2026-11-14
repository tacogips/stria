import Foundation

/// Page summaries live in their own table: no search index reads them.
public extension StriaStore {
  func pageSummary(documentId: String, page: Int) throws -> PageSummaryRecord? {
    let statement = try database.prepare(Self.summarySelect + "WHERE s.document_id=? AND s.page_number=?")
    try statement.bind(documentId, at: 1).bind(page, at: 2)
    guard try statement.step() else { return nil }
    return try summaryRecord(statement)
  }

  func pageSummaries(documentId: String) throws -> [PageSummaryRecord] {
    let statement = try database.prepare(Self.summarySelect + "WHERE s.document_id=? ORDER BY s.page_number")
    try statement.bind(documentId, at: 1)
    var records: [PageSummaryRecord] = []
    while try statement.step() { records.append(try summaryRecord(statement)) }
    return records
  }

  /// Saves a summary (or a failure) for a page, remembering which OCR text
  /// it was based on so a later OCR run marks it stale.
  func savePageSummary(_ record: PageSummaryRecord) throws {
    let statement = try database.prepare("""
      INSERT INTO page_summaries(document_id,page_number,status,summary,error,language,instruction,vendor,model,
        source_ocr_updated_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,(SELECT ocr_updated_at FROM pages WHERE document_id=? AND page_number=?),?)
      ON CONFLICT(document_id,page_number) DO UPDATE SET status=excluded.status,
        summary=CASE WHEN excluded.status='done' THEN excluded.summary ELSE page_summaries.summary END,
        error=excluded.error,language=excluded.language,instruction=excluded.instruction,vendor=excluded.vendor,
        model=excluded.model,source_ocr_updated_at=excluded.source_ocr_updated_at,updated_at=excluded.updated_at
      """)
    try statement.bind(record.documentId, at: 1).bind(record.pageNumber, at: 2).bind(record.status.rawValue, at: 3)
      .bind(record.summary, at: 4).bind(record.error, at: 5).bind(record.language, at: 6).bind(record.instruction, at: 7)
      .bind(record.vendor, at: 8).bind(record.model, at: 9).bind(record.documentId, at: 10).bind(record.pageNumber, at: 11)
      .bind(StriaDateFormat.string(from: record.updatedAt), at: 12)
    _ = try statement.step()
  }

  /// Pages whose OCR is done and that lack a current summary.
  func pagesNeedingSummary(documentId: String) throws -> [Int] {
    let statement = try database.prepare("""
      SELECT p.page_number FROM pages p
      LEFT JOIN page_summaries s ON s.document_id=p.document_id AND s.page_number=p.page_number
      WHERE p.document_id=? AND p.ocr_status='done'
        AND (s.status IS NULL OR s.status<>'done' OR s.source_ocr_updated_at IS NOT p.ocr_updated_at)
      ORDER BY p.page_number
      """)
    try statement.bind(documentId, at: 1)
    var pages: [Int] = []
    while try statement.step() { pages.append(statement.int(0)) }
    return pages
  }

  private static let summarySelect = """
    SELECT s.document_id,s.page_number,s.status,s.summary,s.error,s.language,s.instruction,s.vendor,s.model,s.updated_at,
      s.source_ocr_updated_at IS NOT p.ocr_updated_at
    FROM page_summaries s LEFT JOIN pages p ON p.document_id=s.document_id AND p.page_number=s.page_number

    """

  private func summaryRecord(_ statement: Statement) throws -> PageSummaryRecord {
    guard let documentId = statement.string(0), let status = statement.string(2).flatMap(PageSummaryStatus.init(rawValue:)),
          let vendor = statement.string(7), let updated = statement.string(9).flatMap(StriaDateFormat.date(from:)) else {
      throw StriaError.database("Invalid page summary row")
    }
    return PageSummaryRecord(documentId: documentId, pageNumber: statement.int(1), status: status,
                             summary: statement.string(3), error: statement.string(4),
                             language: statement.string(5) ?? PageSummaryLanguage.auto, instruction: statement.string(6),
                             vendor: vendor, model: statement.string(8), isStale: statement.int(10) != 0, updatedAt: updated)
  }
}

public extension StriaStore {
  /// Summary coverage of every document, keyed by document id.
  func pageSummaryCounts() throws -> [String: PageSummaryCounts] {
    let statement = try database.prepare("""
      SELECT p.document_id,
        SUM(p.ocr_status<>'done'),
        SUM(p.ocr_status='done' AND s.status IS NULL),
        SUM(p.ocr_status='done' AND s.status='done' AND s.source_ocr_updated_at IS p.ocr_updated_at),
        SUM(p.ocr_status='done' AND s.status='failed'),
        SUM(p.ocr_status='done' AND s.status='done' AND s.source_ocr_updated_at IS NOT p.ocr_updated_at),
        COUNT(*)
      FROM pages p
      LEFT JOIN page_summaries s ON s.document_id=p.document_id AND s.page_number=p.page_number
      GROUP BY p.document_id
      """)
    var counts: [String: PageSummaryCounts] = [:]
    while try statement.step() {
      guard let id = statement.string(0) else { continue }
      counts[id] = PageSummaryCounts(done: statement.int(3), failed: statement.int(4), stale: statement.int(5),
                                     missing: statement.int(2), notOCRed: statement.int(1), total: statement.int(6))
    }
    return counts
  }
}
